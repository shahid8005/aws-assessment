data "aws_region" "current" {}
data "aws_caller_identity" "current" {}
data "aws_caller_identity" "me" {}
data "aws_iam_policy_document" "kms_logs" {
  statement {
    sid     = "AllowAccountAdmin"
    effect  = "Allow"
    actions = ["kms:*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
    resources = ["*"]
  }

  statement {
    sid    = "AllowCloudWatchLogsUseKey"
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    principals {
      type        = "Service"
      identifiers = ["logs.${data.aws_region.current.name}.amazonaws.com"]
    }
    resources = ["*"]
  }
}

resource "aws_kms_key" "cw_logs" {
  description         = "KMS for CloudWatch Logs ${var.project} ${var.region}"
  enable_key_rotation = true
  policy              = data.aws_iam_policy_document.kms_logs.json
}

resource "aws_kms_key" "ddb" {
  description         = "KMS for DynamoDB ${var.project} ${var.region}"
  enable_key_rotation = true
}
# ---------- DynamoDB ----------
# ---------- DynamoDB ----------
resource "aws_dynamodb_table" "logs" {
  name         = "${var.project}-GreetingLogs-${var.region}"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"
  range_key    = "sk"

  attribute {
    name = "pk"
    type = "S"
  }

  attribute {
    name = "sk"
    type = "S"
  }

  server_side_encryption {
    enabled     = true
    kms_key_arn = aws_kms_key.ddb.arn
  }

  point_in_time_recovery {
    enabled = true
  }
}
# ---------- Networking (public-only to avoid NAT) ----------
resource "aws_vpc" "vpc" {
  cidr_block           = "10.${substr(replace(var.region, "-", ""), 0, 1)}.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags                 = { Name = "${var.project}-vpc-${var.region}" }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.vpc.id
}

data "aws_availability_zones" "azs" {}

resource "aws_subnet" "public_a" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.${substr(replace(var.region, "-", ""), 0, 1)}.1.0/24"
  availability_zone       = data.aws_availability_zones.azs.names[0]
  map_public_ip_on_launch = false
}

resource "aws_subnet" "public_b" {
  vpc_id                  = aws_vpc.vpc.id
  cidr_block              = "10.${substr(replace(var.region, "-", ""), 0, 1)}.2.0/24"
  availability_zone       = data.aws_availability_zones.azs.names[1]
  map_public_ip_on_launch = false
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "a" {
  subnet_id      = aws_subnet.public_a.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "b" {
  subnet_id      = aws_subnet.public_b.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "fargate_sg" {
  name        = "${var.project}-fargate-sg-${var.region}"
  description = "Fargate outbound only"
  vpc_id      = aws_vpc.vpc.id

  #egress {
  #from_port   = 0
  #to_port     = 0
  # protocol    = "-1"
  #  cidr_blocks = ["0.0.0.0/0"]
  # }
  egress {
    description = "Allow HTTPS outbound only"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ---------- ECS ----------
resource "aws_ecs_cluster" "cluster" {
  name = "${var.project}-cluster-${var.region}"
  setting {
    name  = "containerInsights"
    value = "enabled"
  }
}

resource "aws_cloudwatch_log_group" "ecs" {
  name              = "/ecs/${var.project}-${var.region}"
  retention_in_days = 365
  kms_key_id        = aws_kms_key.cw_logs.arn
}

data "aws_iam_policy_document" "ecs_task_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "ecs_task_role" {
  name               = "${var.project}-ecs-task-role-${var.region}"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

resource "aws_iam_role_policy" "ecs_task_policy" {
  name = "${var.project}-ecs-task-policy-${var.region}"
  role = aws_iam_role.ecs_task_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["sns:Publish"], Resource = var.sns_topic_arn },
      { Effect = "Allow", Action = ["logs:CreateLogStream", "logs:PutLogEvents"], Resource = "${aws_cloudwatch_log_group.ecs.arn}:*" }
    ]
  })
}

resource "aws_iam_role" "ecs_exec_role" {
  name               = "${var.project}-ecs-exec-role-${var.region}"
  assume_role_policy = data.aws_iam_policy_document.ecs_task_assume.json
}

resource "aws_iam_role_policy_attachment" "ecs_exec_attach" {
  role       = aws_iam_role.ecs_exec_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

locals {
  ecs_message = jsonencode({
    email  = var.email
    source = "ECS"
    region = var.region
    repo   = var.repo_url
  })
}

resource "aws_ecs_task_definition" "task" {
  family                   = "${var.project}-task-${var.region}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = "256"
  memory                   = "512"
  execution_role_arn       = aws_iam_role.ecs_exec_role.arn
  task_role_arn            = aws_iam_role.ecs_task_role.arn

  container_definitions = jsonencode([
    {
      name      = "publisher"
      image     = "amazon/aws-cli:2.15.39"
      essential = true
      environment = [
        { name = "SNS_TOPIC_ARN", value = var.sns_topic_arn },
        { name = "MESSAGE", value = local.ecs_message }
      ]
      command = [
        "sns", "publish",
        "--topic-arn", "$SNS_TOPIC_ARN",
        "--message", "$MESSAGE",
        "--region", "us-east-1"
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          awslogs-group         = aws_cloudwatch_log_group.ecs.name
          awslogs-region        = var.region
          awslogs-stream-prefix = "publisher"
        }
      }
    }
  ])
}

# ---------- Lambda packaging ----------
data "archive_file" "greeter_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/greeter.py"
  output_path = "${path.module}/greeter.zip"
}

data "archive_file" "dispatcher_zip" {
  type        = "zip"
  source_file = "${path.module}/lambda_src/dispatcher.py"
  output_path = "${path.module}/dispatcher.zip"
}

data "aws_iam_policy_document" "lambda_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lambda_role" {
  name               = "${var.project}-lambda-role-${var.region}"
  assume_role_policy = data.aws_iam_policy_document.lambda_assume.json
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "${var.project}-lambda-policy-${var.region}"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      { Effect = "Allow", Action = ["dynamodb:PutItem"], Resource = aws_dynamodb_table.logs.arn },
      { Effect = "Allow", Action = ["sns:Publish"], Resource = var.sns_topic_arn },
      { Effect = "Allow", Action = ["ecs:RunTask"], Resource = aws_ecs_task_definition.task.arn },
      { Effect = "Allow", Action = ["iam:PassRole"], Resource = [aws_iam_role.ecs_exec_role.arn, aws_iam_role.ecs_task_role.arn] },
      {
        Effect = "Allow",
        Action = ["logs:CreateLogStream", "logs:PutLogEvents"],
        Resource = [
          "${aws_cloudwatch_log_group.greeter.arn}:*",
          "${aws_cloudwatch_log_group.dispatcher.arn}:*"
        ]
      }
    ]
  })
}

resource "aws_lambda_function" "greeter" {
  function_name = "${var.project}-greeter-${var.region}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "greeter.handler"
  runtime       = "python3.12"
  filename      = data.archive_file.greeter_zip.output_path

  environment {
    variables = {
      TABLE_NAME  = aws_dynamodb_table.logs.name
      SNS_ARN     = var.sns_topic_arn
      EMAIL       = var.email
      REPO_URL    = var.repo_url
      REGION_NAME = var.region
    }
  }
}

resource "aws_lambda_function" "dispatcher" {
  function_name = "${var.project}-dispatcher-${var.region}"
  role          = aws_iam_role.lambda_role.arn
  handler       = "dispatcher.handler"
  runtime       = "python3.12"
  filename      = data.archive_file.dispatcher_zip.output_path

  environment {
    variables = {
      CLUSTER_ARN  = aws_ecs_cluster.cluster.arn
      TASKDEF_ARN  = aws_ecs_task_definition.task.arn
      SUBNETS      = join(",", [aws_subnet.public_a.id, aws_subnet.public_b.id])
      SECURITY_GRP = aws_security_group.fargate_sg.id
      REGION_NAME  = var.region
    }
  }
}

# ---------- API Gateway (HTTP API) + Cognito JWT authorizer ----------
resource "aws_apigatewayv2_api" "api" {
  name          = "${var.project}-api-${var.region}"
  protocol_type = "HTTP"
}

resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id          = aws_apigatewayv2_api.api.id
  authorizer_type = "JWT"
  name            = "cognito-jwt"

  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = var.cognito_issuer_url
    audience = [var.cognito_user_pool_client_id]
  }
}

resource "aws_apigatewayv2_integration" "greet_integ" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.greeter.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_integration" "dispatch_integ" {
  api_id                 = aws_apigatewayv2_api.api.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.dispatcher.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "greet" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "GET /greet"
  target    = "integrations/${aws_apigatewayv2_integration.greet_integ.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_route" "dispatch" {
  api_id    = aws_apigatewayv2_api.api.id
  route_key = "POST /dispatch"
  target    = "integrations/${aws_apigatewayv2_integration.dispatch_integ.id}"

  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.api.id
  name        = "$default"
  auto_deploy = true
}

resource "aws_lambda_permission" "allow_apigw_greet" {
  statement_id  = "AllowAPIGWInvokeGreeter"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.greeter.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

resource "aws_lambda_permission" "allow_apigw_dispatch" {
  statement_id  = "AllowAPIGWInvokeDispatcher"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.dispatcher.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}
