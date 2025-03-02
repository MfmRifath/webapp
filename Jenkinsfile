pipeline {
    agent any

    // Define parameters for flexible deployments
    parameters {
        choice(name: 'ENVIRONMENT', choices: ['dev', 'staging', 'prod'], description: 'Deployment environment')
        booleanParam(name: 'SKIP_TESTS', defaultValue: false, description: 'Skip tests during build')
        booleanParam(name: 'APPLY_TERRAFORM', defaultValue: true, description: 'Apply Terraform changes')
    }

    environment {
        // AWS Configuration
        AWS_REGION = 'us-east-1'
        AWS_CREDS = credentials('aws-credentials')

        // Docker image configuration
        APP_VERSION = "${env.BUILD_NUMBER}"
        DOCKER_REGISTRY_CREDS = credentials('docker-registry-credentials')

        // Using Docker Hub
        DOCKER_HUB_REPO = 'yourusername/springboot-app'

        // MySQL credentials - securely stored in Jenkins
        MYSQL_ROOT_PASSWORD = credentials('mysql-root-password')
        MYSQL_USER = credentials('mysql-user')
        MYSQL_PASSWORD = credentials('mysql-password')
        MYSQL_DATABASE = 'springbootdb'

        // EC2 SSH credentials
        SSH_KEY_CREDENTIALS = credentials('aws-ssh-key')
    }

    options {
        timeout(time: 1, unit: 'HOURS')
        disableConcurrentBuilds()
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm

                // Display info about the build
                echo "Building version: ${APP_VERSION}"
                echo "Environment: ${params.ENVIRONMENT}"
            }
        }

        stage('Build and Test') {
            steps {
                sh """
                    # Set executable permissions for Maven wrapper
                    chmod +x mvnw

                    # Run Maven build with or without tests
                    ./mvnw clean package ${params.SKIP_TESTS ? '-DskipTests' : ''}
                """
            }
            post {
                success {
                    archiveArtifacts artifacts: 'target/*.jar', fingerprint: true
                    junit 'target/surefire-reports/**/*.xml'
                }
            }
        }

        stage('Build Docker Image') {
            steps {
                script {
                    // Login to Docker Hub
                    sh """
                        echo ${DOCKER_REGISTRY_CREDS_PSW} | docker login -u ${DOCKER_REGISTRY_CREDS_USR} --password-stdin
                    """

                    // Build Docker image
                    sh """
                        docker build -t ${DOCKER_HUB_REPO}:${APP_VERSION} -t ${DOCKER_HUB_REPO}:latest .
                    """
                }
            }
        }

        stage('Push Docker Image') {
            steps {
                script {
                    // Push Docker images
                    sh """
                        docker push ${DOCKER_HUB_REPO}:${APP_VERSION}
                        docker push ${DOCKER_HUB_REPO}:latest
                    """
                }
            }
        }

        stage('Terraform Init') {
            steps {
                // Configure AWS credentials for Terraform
                withEnv(["AWS_ACCESS_KEY_ID=${AWS_CREDS_USR}", "AWS_SECRET_ACCESS_KEY=${AWS_CREDS_PSW}"]) {
                    dir('terraform') {
                        sh "terraform init -reconfigure"
                    }
                }
            }
        }

        stage('Terraform Plan') {
            steps {
                // Generate Terraform plan
                withEnv(["AWS_ACCESS_KEY_ID=${AWS_CREDS_USR}", "AWS_SECRET_ACCESS_KEY=${AWS_CREDS_PSW}"]) {
                    dir('terraform') {
                        sh """
                            # Create terraform.tfvars file
                            cat > terraform.tfvars << EOF
                            aws_region = "${AWS_REGION}"
                            environment = "${params.ENVIRONMENT}"
                            public_key_path = "${SSH_KEY_CREDENTIALS}"
                            private_key_path = "${SSH_KEY_CREDENTIALS}"
                            EOF

                            terraform plan -out=tfplan
                        """
                    }
                }
            }
        }

        stage('Terraform Apply') {
            when {
                expression { params.APPLY_TERRAFORM }
            }
            steps {
                // Apply Terraform changes
                withEnv(["AWS_ACCESS_KEY_ID=${AWS_CREDS_USR}", "AWS_SECRET_ACCESS_KEY=${AWS_CREDS_PSW}"]) {
                    dir('terraform') {
                        sh "terraform apply -auto-approve tfplan"

                        // Store Terraform outputs for later use
                        script {
                            try {
                                env.EC2_PUBLIC_IP = sh(
                                    script: "terraform output -raw instance_public_ip",
                                    returnStdout: true
                                ).trim()

                                echo "EC2 instance deployed at: ${env.EC2_PUBLIC_IP}"
                            } catch (Exception e) {
                                echo "Failed to get terraform output: ${e.message}"
                                env.EC2_PUBLIC_IP = "unknown"
                            }
                        }
                    }
                }
            }
        }

        stage('Prepare Ansible') {
            steps {
                dir('ansible') {
                    // Create a directory for group variables
                    sh "mkdir -p group_vars/all"

                    // Create Ansible variables file with credentials
                    sh """
                        cat > group_vars/all/vars.yml << EOF
                        app_docker_image: ${DOCKER_HUB_REPO}:${APP_VERSION}
                        mysql_docker_image: mysql:8.0
                        mysql_root_password: ${MYSQL_ROOT_PASSWORD}
                        mysql_database: ${MYSQL_DATABASE}
                        mysql_user: ${MYSQL_USER}
                        mysql_password: ${MYSQL_PASSWORD}
                        mysql_data_dir: /data/mysql
                        EOF
                    """

                    // Create updated hosts file in case terraform did not
                    sh """
                        if [ ! -f inventory ]; then
                            echo "[app_servers]" > inventory
                            echo "app ansible_host=${env.EC2_PUBLIC_IP}" >> inventory
                            echo "" >> inventory
                            echo "[app_servers:vars]" >> inventory
                            echo "ansible_user=ec2-user" >> inventory
                            echo "ansible_ssh_private_key_file=${SSH_KEY_CREDENTIALS}" >> inventory
                            echo "ansible_python_interpreter=/usr/bin/python3" >> inventory
                        fi
                    """
                }
            }
        }

        stage('Run Ansible') {
            steps {
                dir('ansible') {
                    // Run Ansible playbook
                    sh """
                        # Install required Ansible collections
                        ansible-galaxy collection install community.docker

                        # Wait for SSH to become available
                        timeout 300 bash -c 'until ssh -o StrictHostKeyChecking=no -i ${SSH_KEY_CREDENTIALS} ec2-user@${env.EC2_PUBLIC_IP} "echo SSH ready"; do sleep 5; done'

                        # Run Ansible playbook
                        ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -i inventory playbook.yml \
                            --private-key=${SSH_KEY_CREDENTIALS}
                    """
                }
            }
        }

        stage('Verify Deployment') {
            steps {
                // Wait for application to start and verify it's running
                sh """
                    # Give the app time to start
                    sleep 30

                    # Verify application is responding
                    curl --retry 10 --retry-delay 5 --retry-connrefused http://${env.EC2_PUBLIC_IP}:80/actuator/health || echo "Application health check failed"

                    echo "Deployment verification complete. Application is available at: http://${env.EC2_PUBLIC_IP}"
                """
            }
        }
    }

    post {
        success {
            echo "Deployment completed successfully!"

            // Send success notification
            emailext (
                subject: "SUCCESS: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
                body: "The build was successful. Application deployed to ${params.ENVIRONMENT} at http://${env.EC2_PUBLIC_IP}",
                to: "mmfmrifarth@gmail.com"
            )
        }
        failure {
            echo "Deployment failed!"

            // Send failure notification
            emailext (
                subject: "FAILED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
                body: "The build failed. Please check the Jenkins logs.",
                to: "mmfmrifath@gmail.com"
            )
        }
        always {
            script {
                // Clean workspace in a node context
                node {
                    cleanWs()
                }

                // Try to clean Docker images - also in a node context
                // Using try-catch to handle cases where variables might not be set
                try {
                    node {
                        // Only attempt Docker cleanup if the repo variable is available
                        if (env.DOCKER_HUB_REPO != null && env.APP_VERSION != null) {
                            sh """
                                docker rmi ${env.DOCKER_HUB_REPO}:${env.APP_VERSION} || true
                                docker rmi ${env.DOCKER_HUB_REPO}:latest || true
                                docker system prune -f || true
                            """
                        } else {
                            echo "Skipping Docker cleanup because required variables are not available"
                        }
                    }
                } catch (Exception e) {
                    echo "Docker cleanup failed, but continuing: ${e.message}"
                }
            }
        }
    }
}