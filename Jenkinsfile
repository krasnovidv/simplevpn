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
                sh """
                    sshpass -p "\${VPS_CREDS_PSW}" ssh -o StrictHostKeyChecking=no \${VPS_USER}@\${VPS_HOST} \
                        "sleep 3 && docker logs --tail 10 \${CONTAINER_NAME}"
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
