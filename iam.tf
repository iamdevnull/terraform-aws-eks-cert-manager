locals {
  k8s_irsa_role_create = var.enabled && var.k8s_rbac_create && var.k8s_service_account_create && var.k8s_irsa_role_create
}

data "aws_iam_policy_document" "this" {
  count = local.k8s_irsa_role_create ? 1 : 0

  dynamic "statement" {
    for_each = var.k8s_irsa_policy_enabled ? toset(["true"]) : []
    content {
      sid    = "ChangeResourceRecordSets"
      effect = "Allow"
      actions = [
        "route53:ChangeResourceRecordSets",
      ]
      resources = formatlist(
        "arn:aws:route53:::hostedzone/%s",
        var.policy_allowed_zone_ids
      )

    }
  }

  dynamic "statement" {
    for_each = var.k8s_irsa_policy_enabled ? toset(["true"]) : []
    content {
      sid    = "ListResourceRecordSets"
      effect = "Allow"
      actions = [
        "route53:ListHostedZones",
        "route53:ListResourceRecordSets",
        "route53:ListTagsForResource",
        "route53:ListHostedZonesByName"
      ]
      resources = [
        "*"
      ]
    }
  }

  dynamic "statement" {
    for_each = var.k8s_irsa_policy_enabled ? toset(["true"]) : []
    content {
      sid    = "GetBatchChangeStatus"
      effect = "Allow"
      actions = [
        "route53:GetChange"
      ]
      resources = [
        "*"
      ]
    }
  }

  dynamic "statement" {
    for_each = var.k8s_assume_role_enabled ? toset(["true"]) : []
    content {
      sid    = "AllowAssumeCertManagerRole"
      effect = "Allow"
      actions = [
        "sts:AssumeRole"
      ]
      resources = var.k8s_assume_role_arns
    }
  }
}

resource "aws_iam_policy" "this" {
  count = local.k8s_irsa_role_create && (var.k8s_irsa_policy_enabled || var.k8s_irsa_policy_enabled) ? 1 : 0

  name        = "${var.k8s_irsa_role_name_prefix}-${var.helm_chart_name}"
  path        = "/"
  description = "Policy for cert-manager service"
  policy      = data.aws_iam_policy_document.this[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "this_irsa" {
  count = local.k8s_irsa_role_create ? 1 : 0

  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.cluster_identity_oidc_issuer_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(var.cluster_identity_oidc_issuer, "https://", "")}:sub"

      values = [
        "system:serviceaccount:${var.k8s_namespace}:${var.k8s_service_account_name}",
      ]
    }

    effect = "Allow"
  }
}

resource "aws_iam_role" "this" {
  count = local.k8s_irsa_role_create ? 1 : 0

  name               = "${var.k8s_irsa_role_name_prefix}-${var.helm_chart_name}"
  assume_role_policy = data.aws_iam_policy_document.this_irsa[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "this" {
  count = local.k8s_irsa_role_create ? 1 : 0

  role       = aws_iam_role.this[0].name
  policy_arn = aws_iam_policy.this[0].arn
}

resource "aws_iam_role_policy_attachment" "this_additional" {
  for_each = local.k8s_irsa_role_create ? var.k8s_irsa_additional_policies : {}

  role       = aws_iam_role.this[0].name
  policy_arn = each.value
}
