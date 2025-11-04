pipeline { 
  agent any

  environment {
    AWS_REGION       = 'us-east-1'
    AWS_ACCOUNT_ID   = '541614060542'
    ECR_REPO_NAME    = 'dev-python'
    ECS_CLUSTER      = 'DEV-Cluster'
    ECS_SERVICE      = 'dev-python-service'
    CONTAINER_NAME   = 'dev-python-container'
    IMAGE_TAG        = "${env.BUILD_ID}"
    GIT_CREDENTIALS  = 'github-ssh'
    AWS_CREDENTIALS  = 'aws-creds'
    TEST_RESULTS     = 'test-results'

    // SonarQube variables
    SONARQUBE_SERVER = 'SonarQubeServer'   // Jenkins SonarQube server name
    SONARQUBE_SCANNER = 'SonarQubeScanner' // Jenkins SonarQube scanner tool name
    SONAR_HOST_URL   = 'https://sonarqube.yourcompany.com' // Replace with your SonarQube URL
    SONAR_AUTH_TOKEN = credentials('sonarqube-token') // Jenkins credential ID for token
  }

  options {
    buildDiscarder(logRotator(numToKeepStr: '10'))
    timestamps()
    timeout(time: 50, unit: 'MINUTES')
  }

  stages {
    stage('Checkout') {
      steps {
        checkout([
          $class: 'GitSCM',
          branches: [[name: '*/main']],
          userRemoteConfigs: [[url: 'git@github.com:your-org/your-repo.git', credentialsId: "${env.GIT_CREDENTIALS}"]]
        ])
      }
    }

    stage('Install deps & Unit tests') {
      steps {
        sh '''
          python3 -m venv .venv
          . .venv/bin/activate
          pip install -r requirements.txt
          mkdir -p ${TEST_RESULTS}
          if [ -d tests ]; then
            pip install pytest pytest-cov
            pytest -q --junitxml=${TEST_RESULTS}/unit-tests.xml || exit 1
          fi
        '''
        junit "${TEST_RESULTS}/unit-tests.xml"
      }
    }

    //  SonarQube Analysis
    stage('SonarQube Analysis') {
      environment {
        SCANNER_HOME = tool "${SONARQUBE_SCANNER}"
      }
      steps {
        withSonarQubeEnv("${SONARQUBE_SERVER}") {
          script {
            sh """
              ${SCANNER_HOME}/bin/sonar-scanner \
                -Dsonar.projectKey=${ECR_REPO_NAME} \
                -Dsonar.projectName=${ECR_REPO_NAME} \
                -Dsonar.projectVersion=${BUILD_ID} \
                -Dsonar.sources=. \
                -Dsonar.host.url=${SONAR_HOST_URL} \
                -Dsonar.login=${SONAR_AUTH_TOKEN}
            """
          }
        }
      }
      post {
        success {
          echo 'SonarQube analysis completed successfully.'
        }
        failure {
          echo 'SonarQube analysis failed.'
        }
      }
    }

    // Optional — wait for SonarQube Quality Gate
    stage('Quality Gate') {
      steps {
        timeout(time: 5, unit: 'MINUTES') {
          waitForQualityGate abortPipeline: true
        }
      }
    }

    stage('Build Docker Image') {
      steps {
        script {
          def commit = sh(returnStdout: true, script: 'git rev-parse --short HEAD').trim()
          env.IMAGE_TAG = "${commit}-${env.BUILD_ID}"
          env.IMAGE_URI = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_REGION}.amazonaws.com/${env.ECR_REPO_NAME}:${env.IMAGE_TAG}"
        }
        sh "docker build -t ${ECR_REPO_NAME}:${IMAGE_TAG} ."
      }
    }

    stage('Push to ECR') {
      steps {
        script {
          withCredentials([usernamePassword(credentialsId: "${env.AWS_CREDENTIALS}", usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
            sh '''
              aws configure set default.region ${AWS_REGION}
              aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com
              aws ecr describe-repositories --repository-names "${ECR_REPO_NAME}" --region ${AWS_REGION} || aws ecr create-repository --repository-name "${ECR_REPO_NAME}" --region ${AWS_REGION}
              docker tag ${ECR_REPO_NAME}:${IMAGE_TAG} ${IMAGE_URI}
              docker push ${IMAGE_URI}
            '''
          }
        }
      }
    }

    stage('Register Task Definition & Update ECS Service') {
      steps {
        script {
          sh '''
            cat > taskdef.json <<EOF
            {
              "family": "${ECR_REPO_NAME}",
              "networkMode": "awsvpc",
              "requiresCompatibilities": ["FARGATE"],
              "cpu": "512",
              "memory": "1024",
              "executionRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecsTaskExecutionRole",
              "taskRoleArn": "arn:aws:iam::${AWS_ACCOUNT_ID}:role/ecsTaskRole",
              "containerDefinitions": [
                {
                  "name": "${CONTAINER_NAME}",
                  "image": "${IMAGE_URI}",
                  "essential": true,
                  "portMappings": [{"containerPort": 8000, "protocol": "tcp"}],
                  "environment": [{"name":"ENV","value":"prod"}],
                  "logConfiguration": {
                    "logDriver": "awslogs",
                    "options": {
                      "awslogs-group": "/ecs/${ECR_REPO_NAME}",
                      "awslogs-region": "${AWS_REGION}",
                      "awslogs-stream-prefix": "${CONTAINER_NAME}"
                    }
                  }
                }
              ]
            }
            EOF

            aws ecs register-task-definition --cli-input-json file://taskdef.json --region ${AWS_REGION} > taskreg.json
            NEW_TD_ARN=$(jq -r '.taskDefinition.taskDefinitionArn' taskreg.json)
            aws ecs update-service --cluster ${ECS_CLUSTER} --service ${ECS_SERVICE} --task-definition "${NEW_TD_ARN}" --region ${AWS_REGION}
          '''
        }
      }
    }
  }

  post {
    success {
      echo "Deployment success: ${IMAGE_URI}"
    }
    failure {
      echo "Pipeline failed — check console and test reports."
    }
  }
}
