resource "aws_dynamodb_table" "mcp_users" {
  name         = "quick-mcp-poc-users"
  billing_mode   = "PROVISIONED"
  read_capacity  = 5
  write_capacity = 5
  hash_key     = "PK"

  attribute {
    name = "PK"
    type = "S"
  }

  tags = {
    Name = "quick-mcp-poc-users"
  }
}
