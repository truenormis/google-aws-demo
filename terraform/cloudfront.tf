# CloudFront distribution in front of ALB for static asset caching

locals {
  is_production    = terraform.workspace == "production"
  cloudfront_domain = local.is_production ? var.domain_name : "staging.${var.domain_name}"
  origin_domain     = local.is_production ? "origin.${var.domain_name}" : "origin-staging.${var.domain_name}"
}

# ACM certificate in us-east-1 (required by CloudFront)
resource "aws_acm_certificate" "cloudfront" {
  provider    = aws.us_east_1
  domain_name = local.cloudfront_domain
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "cloudflare_record" "cloudfront_acm_validation" {
  for_each = {
    for dvo in aws_acm_certificate.cloudfront.domain_validation_options : dvo.domain_name => {
      name    = dvo.resource_record_name
      type    = dvo.resource_record_type
      content = dvo.resource_record_value
    }
  }

  zone_id         = var.cloudflare_zone_id
  name            = each.value.name
  type            = each.value.type
  content         = trimsuffix(each.value.content, ".")
  proxied         = false
  ttl             = 60
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "cloudfront" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.cloudfront.arn
  validation_record_fqdns = [for record in cloudflare_record.cloudfront_acm_validation : record.hostname]
}

# Managed cache policies
data "aws_cloudfront_cache_policy" "caching_optimized" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "caching_disabled" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "all_viewer_except_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

# CloudFront distribution
resource "aws_cloudfront_distribution" "main" {
  enabled         = true
  is_ipv6_enabled = true
  aliases         = [local.cloudfront_domain]
  price_class     = var.cloudfront_price_class
  comment         = "${var.project_name} ${terraform.workspace}"

  origin {
    domain_name = local.origin_domain
    origin_id   = "alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # Default behavior — dynamic content, no caching
  default_cache_behavior {
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id          = data.aws_cloudfront_cache_policy.caching_disabled.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.all_viewer_except_host.id
  }

  # Static assets — cached for 24h
  ordered_cache_behavior {
    path_pattern           = "/static/*"
    target_origin_id       = "alb"
    viewer_protocol_policy = "redirect-to-https"
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true

    cache_policy_id = data.aws_cloudfront_cache_policy.caching_optimized.id
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.cloudfront.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  depends_on = [aws_acm_certificate_validation.cloudfront]
}

# DNS: point main domain to CloudFront
resource "cloudflare_record" "cloudfront" {
  zone_id         = var.cloudflare_zone_id
  name            = local.cloudfront_domain
  type            = "CNAME"
  content         = aws_cloudfront_distribution.main.domain_name
  proxied         = false
  ttl             = 300
  allow_overwrite = true
}
