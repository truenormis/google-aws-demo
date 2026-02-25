locals {
  ecr_repositories = {
    frontend              = "${var.project_name}/frontend"
    productcatalogservice = "${var.project_name}/productcatalogservice"
    currencyservice       = "${var.project_name}/currencyservice"
  }
}

resource "aws_ecr_repository" "app" {
  for_each             = local.ecr_repositories
  name                 = each.value
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_lifecycle_policy" "app" {
  for_each   = local.ecr_repositories
  repository = aws_ecr_repository.app[each.key].name

  policy = jsonencode({
    rules = [{
      rulePriority = 1
      description  = "Keep last 10 images"
      selection = {
        tagStatus   = "any"
        countType   = "imageCountMoreThan"
        countNumber = 10
      }
      action = {
        type = "expire"
      }
    }]
  })
}
