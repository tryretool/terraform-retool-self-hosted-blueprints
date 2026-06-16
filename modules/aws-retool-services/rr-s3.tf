# S3 bucket and IAM service account for Retool Remote Repository (RR) storage.

resource "aws_s3_bucket" "rr" {
  count  = var.enable_rr_s3 ? 1 : 0
  bucket = "retool-${var.prefix}-rr"
  tags   = local.all_tags
}

resource "aws_s3_bucket_public_access_block" "rr" {
  count  = var.enable_rr_s3 ? 1 : 0
  bucket = aws_s3_bucket.rr[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_user" "rr" {
  count = var.enable_rr_s3 ? 1 : 0
  name  = "${var.prefix}-rr"
  tags  = local.all_tags
}

resource "aws_iam_access_key" "rr" {
  count = var.enable_rr_s3 ? 1 : 0
  user  = aws_iam_user.rr[0].name
}

resource "aws_iam_user_policy" "rr" {
  count = var.enable_rr_s3 ? 1 : 0
  name  = "${var.prefix}-rr-s3"
  user  = aws_iam_user.rr[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = aws_s3_bucket.rr[0].arn
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListMultipartUploadParts",
          "s3:AbortMultipartUpload",
        ]
        Resource = "${aws_s3_bucket.rr[0].arn}/*"
      },
    ]
  })
}

resource "kubernetes_secret_v1" "rr_s3" {
  count = var.enable_rr_s3 ? 1 : 0

  metadata {
    name      = "rr-s3-credentials"
    namespace = local.retool_namespace
  }

  data = {
    RR_BLOB_STORAGE_PROVIDER        = "s3"
    RR_DEFAULT_S3_BUCKET            = aws_s3_bucket.rr[0].id
    RR_DEFAULT_S3_REGION            = var.region
    RR_DEFAULT_S3_ACCESS_KEY_ID     = aws_iam_access_key.rr[0].id
    RR_DEFAULT_S3_SECRET_ACCESS_KEY = aws_iam_access_key.rr[0].secret
  }

  depends_on = [kubernetes_namespace_v1.retool]
}
