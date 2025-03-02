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

        // Other stages remain the same but we'll simplify for now
    }

    post {
        success {
            echo "Deployment completed successfully!"

            // Send success notification
            emailext (
                subject: "SUCCESS: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
                body: "The build was successful. Application deployed to ${params.ENVIRONMENT}",
                to: "team@example.com"
            )
        }
        failure {
            echo "Deployment failed!"

            // Send failure notification
            emailext (
                subject: "FAILED: Job '${env.JOB_NAME} [${env.BUILD_NUMBER}]'",
                body: "The build failed. Please check the Jenkins logs.",
                to: "team@example.com"
            )
        }
        always {
            // Move cleanWs inside a node block
            script {
                node {
                    // Clean workspace within a node context
                    cleanWs()
                }

                // Try to clean Docker images - also in a node context
                node {
                    sh """
                        docker rmi ${DOCKER_HUB_REPO}:${APP_VERSION} || true
                        docker rmi ${DOCKER_HUB_REPO}:latest || true
                        docker system prune -f || true
                    """
                }
            }
        }
    }
}