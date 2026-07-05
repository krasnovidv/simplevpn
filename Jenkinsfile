pipeline {
    agent any

    environment {
        VPS_HOST = '193.23.3.93'
        VPS_USER = 'root'
        REMOTE_DIR = '/opt/simplevpn'
        IMAGE_NAME = 'simplevpn-server'
        CONTAINER_NAME = 'simplevpn-server'
        VPS_CREDS = credentials('simplevpn-vps')
    }

    stages {
        // Quality gates run BEFORE anything is built or deployed, so broken
        // code never reaches the production VPS. Previously the pipeline went
        // straight from Build APK to deploy with no tests at all.
        stage('Go Checks') {
            steps {
                bat 'go vet ./...'
                bat 'go test ./...'
            }
        }

        stage('Flutter Checks') {
            steps {
                dir('mobile/app') {
                    bat 'D:\\flutter\\bin\\flutter.bat analyze'
                    bat 'D:\\flutter\\bin\\flutter.bat test'
                }
            }
        }

        stage('Build APK') {
            steps {
                bat 'D:\\flutter\\bin\\flutter.bat build apk --release'
            }
        }

        stage('Generate Update Manifest') {
            steps {
                script {
                    def pubspec = readFile('mobile/app/pubspec.yaml')
                    def matcher = pubspec =~ /version:\s*(\S+)\+(\d+)/
                    if (!matcher.find()) {
                        error 'Could not parse version from pubspec.yaml'
                    }
                    def versionName = matcher.group(1)
                    def versionCode = matcher.group(2)
                    echo "Extracted version: ${versionName}+${versionCode}"
                    def manifest = """{
  "version": "${versionName}",
  "versionCode": ${versionCode},
  "downloadUrl": "/download/simplevpn.apk",
  "changelog": "Доступна новая версия ${versionName}"
}"""
                    writeFile file: 'update.json', text: manifest
                }
            }
        }

        stage('Deploy to VPS') {
            steps {
                // Sync source files to VPS
                sh """
                    sshpass -p "\${VPS_CREDS_PSW}" scp -o StrictHostKeyChecking=no \
                        Dockerfile deploy/entrypoint.sh go.mod go.sum \
                        \${VPS_USER}@\${VPS_HOST}:\${REMOTE_DIR}/
                """
                sh """
                    sshpass -p "\${VPS_CREDS_PSW}" scp -o StrictHostKeyChecking=no -r \
                        cmd pkg deploy \
                        \${VPS_USER}@\${VPS_HOST}:\${REMOTE_DIR}/
                """

                // Upload APK and update manifest
                sh """
                    sshpass -p "\${VPS_CREDS_PSW}" scp -o StrictHostKeyChecking=no \
                        mobile/app/build/app/outputs/flutter-apk/app-release.apk \
                        \${VPS_USER}@\${VPS_HOST}:\${REMOTE_DIR}/simplevpn.apk
                """
                sh """
                    sshpass -p "\${VPS_CREDS_PSW}" scp -o StrictHostKeyChecking=no \
                        update.json \
                        \${VPS_USER}@\${VPS_HOST}:\${REMOTE_DIR}/update.json
                """

                // Build and restart container on VPS
                sh """
                    sshpass -p "\${VPS_CREDS_PSW}" ssh -o StrictHostKeyChecking=no \${VPS_USER}@\${VPS_HOST} \
                        "cd \${REMOTE_DIR} && \
                         docker build -t \${IMAGE_NAME} . && \
                         docker rm -f \${CONTAINER_NAME} 2>/dev/null; \
                         docker run -d \
                           --name \${CONTAINER_NAME} \
                           --restart unless-stopped \
                           --cap-add NET_ADMIN \
                           --device /dev/net/tun \
                           -v \${REMOTE_DIR}/config:/etc/simplevpn \
                           -v \${REMOTE_DIR}/certs:/etc/simplevpn/certs \
                           -v \${REMOTE_DIR}/simplevpn.apk:/opt/simplevpn/simplevpn.apk:ro \
                           -v \${REMOTE_DIR}/update.json:/opt/simplevpn/update.json:ro \
                           -p 443:443 \
                           -p 8443:8443 \
                           -p 8080:8080 \
                           \${IMAGE_NAME}"
                """
            }
        }

        stage('Health Check') {
            steps {
                // Actually probe /healthz and fail the build if the server
                // isn't serving — the old check just printed logs and always
                // passed, so a crash-looping container looked like a success.
                sh """
                    sshpass -p "\${VPS_CREDS_PSW}" ssh -o StrictHostKeyChecking=no \${VPS_USER}@\${VPS_HOST} \
                        "sleep 5 && \
                         curl -fsS http://127.0.0.1:8080/healthz && echo ' OK' || \
                         (echo 'HEALTHCHECK FAILED'; docker logs --tail 30 \${CONTAINER_NAME}; exit 1)"
                """
            }
        }
    }

    post {
        failure {
            echo 'Deploy failed! Check logs above.'
        }
        success {
            echo "Deployed to ${VPS_HOST}:443"
        }
    }
}
