# -----------------------------------------------------------------------------
# Required Variables
# -----------------------------------------------------------------------------

variable "project_name" {
  description = "Name prefix for all resources (e.g., 'finops-mcp')"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*$", var.project_name))
    error_message = "Project name must start with a letter and contain only lowercase letters, numbers, and hyphens."
  }
}

variable "aws_region" {
  description = "AWS region to deploy resources"
  type        = string
  default     = "us-east-1"
}

# -----------------------------------------------------------------------------
# Lambda Configuration
# -----------------------------------------------------------------------------

variable "lambda_timeout" {
  description = "Lambda function timeout in seconds"
  type        = number
  default     = 30

  validation {
    condition     = var.lambda_timeout >= 1 && var.lambda_timeout <= 900
    error_message = "Lambda timeout must be between 1 and 900 seconds."
  }
}

variable "lambda_memory_size" {
  description = "Lambda function memory size in MB"
  type        = number
  default     = 256

  validation {
    condition     = var.lambda_memory_size >= 128 && var.lambda_memory_size <= 10240
    error_message = "Lambda memory must be between 128 and 10240 MB."
  }
}

# -----------------------------------------------------------------------------
# Gateway Configuration
# -----------------------------------------------------------------------------

variable "gateway_auth_type" {
  description = "Gateway auth: COGNITO (default — auto-provisions a Cognito OAuth client for M2M callers like QuickSuite), CUSTOM_JWT (BYO OIDC IdP for user auth), AWS_IAM (SigV4), or NONE."
  type        = string
  default     = "COGNITO"

  validation {
    condition     = contains(["COGNITO", "CUSTOM_JWT", "AWS_IAM", "NONE"], var.gateway_auth_type)
    error_message = "Gateway auth type must be one of: COGNITO, CUSTOM_JWT, AWS_IAM, NONE."
  }
}

# Federate JWT Configuration (required when gateway_auth_type = CUSTOM_JWT)
variable "jwt_discovery_url" {
  description = "OIDC discovery URL for JWT validation (Amazon Federate)"
  type        = string
  default     = ""
}

variable "jwt_allowed_audiences" {
  description = "List of allowed JWT audiences for gateway authentication"
  type        = list(string)
  default     = []
}

variable "jwt_allowed_clients" {
  description = "List of allowed JWT client IDs (optional, leave empty for all clients)"
  type        = list(string)
  default     = []
}

# Cognito Configuration (used when gateway_auth_type = COGNITO)
variable "cognito_domain_prefix" {
  description = "Cognito hosted-domain prefix (globally unique). Leave empty for auto: '<project_name>-<account_id>'."
  type        = string
  default     = ""
}

variable "cognito_scope_name" {
  description = "Custom OAuth scope name (final scope = '<project_name>/<cognito_scope_name>')."
  type        = string
  default     = "invoke"
}

# -----------------------------------------------------------------------------
# Optional Configuration
# -----------------------------------------------------------------------------

variable "environment" {
  description = "Environment name (e.g., 'dev', 'staging', 'prod')"
  type        = string
  default     = "dev"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default = {
    Project   = "AWS FinOps Agent"
    ManagedBy = "Terraform"
  }
}

# -----------------------------------------------------------------------------
# AWS Profile Configuration
# -----------------------------------------------------------------------------

variable "aws_profile" {
  description = "AWS CLI profile for data collection account"
  type        = string
  default     = ""
}

# -----------------------------------------------------------------------------
# Cross-Account Management Account Configuration
# -----------------------------------------------------------------------------
# For data collection account deployments (alongside CUDOS/CID/KPI dashboards),
# configure access to Cost Explorer and CUR data in the management account.

variable "management_account_profile" {
  description = "AWS CLI profile for management/payer account (empty = single-account mode)"
  type        = string
  default     = ""
}

variable "management_external_id" {
  description = "External ID for cross-account role assumption (auto-generated if empty)"
  type        = string
  default     = ""
  sensitive   = true
}

# -----------------------------------------------------------------------------
# CUR Configuration
# -----------------------------------------------------------------------------

variable "cur_bucket_name" {
  description = "S3 bucket containing CUR data (in management account)"
  type        = string
  default     = "my-cur-cost-export"
}

variable "cur_athena_output_location" {
  description = "S3 location for Athena query results (e.g., s3://my-bucket/athena-results/). If empty, defaults to s3://{cur_bucket_name}/athena-results/"
  type        = string
  default     = ""
}

variable "additional_cur_bucket_names" {
  description = <<-EOT
    Extra S3 buckets holding CUR/Data Exports data that Athena tables point at,
    beyond cur_bucket_name. Granted READ-ONLY (GetObject/ListBucket/GetBucketLocation)
    to the athena-mcp Lambda role. Athena reads S3 with the CALLER's identity, so any
    Glue table in a bucket absent from this list fails at query time with an S3
    permission error even though the table and partitions resolve correctly.
    Set this whenever you register a second export (e.g. a CID/split-cost export in
    its own bucket).
  EOT
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# VPC Configuration
# -----------------------------------------------------------------------------

variable "enable_vpc" {
  description = "Place Lambda functions in a VPC with VPC endpoints (no NAT Gateway needed)"
  type        = bool
  default     = false
}

variable "vpc_cidr" {
  description = "CIDR block for the Lambda VPC (only used when enable_vpc = true)"
  type        = string
  default     = "10.0.0.0/24"
}

# -----------------------------------------------------------------------------
# Lambda Security Configuration
# -----------------------------------------------------------------------------

variable "lambda_reserved_concurrent_executions" {
  description = "Reserved concurrent executions for Lambda functions"
  type        = number
  default     = 10
}

variable "log_retention_in_days" {
  description = "CloudWatch Log Group retention in days (365+ recommended for compliance)"
  type        = number
  default     = 365

  validation {
    condition     = contains([0, 1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_in_days)
    error_message = "log_retention_in_days must be a valid CloudWatch retention value."
  }
}

variable "lambda_kms_key_arn" {
  description = "ARN of KMS key to encrypt Lambda environment variables. If null, AWS managed encryption is used."
  type        = string
  default     = null
}
