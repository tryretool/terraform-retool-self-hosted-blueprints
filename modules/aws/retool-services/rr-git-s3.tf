# S3 bucket and IAM service account for Retool Remote Repository (RR) Git storage.

resource "aws_s3_bucket" "rr_git" {
  count  = var.enable_rr_git_s3 ? 1 : 0
  bucket = "retool-${var.prefix}-rr-git"
  tags   = local.all_tags
}

resource "aws_s3_bucket_public_access_block" "rr_git" {
  count  = var.enable_rr_git_s3 ? 1 : 0
  bucket = aws_s3_bucket.rr_git[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_iam_user" "rr_git" {
  count = var.enable_rr_git_s3 ? 1 : 0
  name  = "${var.prefix}-rr-git"
  tags  = local.all_tags
}

resource "aws_iam_access_key" "rr_git" {
  count = var.enable_rr_git_s3 ? 1 : 0
  user  = aws_iam_user.rr_git[0].name
}

resource "aws_iam_user_policy" "rr_git" {
  count = var.enable_rr_git_s3 ? 1 : 0
  name  = "${var.prefix}-rr-git-s3"
  user  = aws_iam_user.rr_git[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "s3:ListBucket",
          "s3:GetBucketLocation",
        ]
        Resource = aws_s3_bucket.rr_git[0].arn
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
        Resource = "${aws_s3_bucket.rr_git[0].arn}/*"
      },
    ]
  })
}

resource "kubernetes_secret_v1" "rr_git_s3" {
  count = var.enable_rr_git_s3 ? 1 : 0

  metadata {
    name      = "rr-git-s3-credentials"
    namespace = local.retool_namespace
  }

  data = {
    RR_GIT_S3_BUCKET         = aws_s3_bucket.rr_git[0].id
    RR_GIT_S3_REGION         = var.region
    RR_GIT_S3_ACCESS_KEY_ID     = aws_iam_access_key.rr_git[0].id
    RR_GIT_S3_SECRET_ACCESS_KEY = aws_iam_access_key.rr_git[0].secret
  }
}
