locals {
  all_tags = merge(var.default_tags, var.tags, { "aws-apn-id" = "pc:eb361b0frzt279bzrk1zwdk0w" })
}
