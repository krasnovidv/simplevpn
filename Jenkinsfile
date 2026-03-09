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
                           -p 443:443 \
                           -p 8443:8443 \
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
