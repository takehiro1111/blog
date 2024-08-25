---
title: "[Terraform]AWS Budgetアラート通知をSNS,Chatbot経由でSlack通知"
emoji: "🙆"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["AWS","Terraform","コスト","Slack"]
published: true
---
![](/images/terraform_logo.png)

## 前提
- terraformにおけるprovider等の準備段階で必要な設定の記載は省略しています。

## 要件
- AWSの月次使用金額の状況を把握したい.
- 段階ごとに設定したBudgetの閾値を超過した場合はSlackへアラート通知を行いたい。

## 構成
![](/images/alert/budget_slack_notify.png)

## 結果イメージ
- 以下画像のようにBudgetで設定した閾値を超過した際にSLack通知が飛ぶこと。
![](/images/alert/result.png)

&nbsp;
## Slackで予め必要な設定
### 1.`slack app directory`にて、`AWS Chatbot`を自身のSlackワークスペースで使用出来るよう承認、追加する。
https://slack.com/intl/ja-jp/help/articles/222386767-%E3%83%AF%E3%83%BC%E3%82%AF%E3%82%B9%E3%83%9A%E3%83%BC%E3%82%B9%E3%81%A7%E4%BD%BF%E7%94%A8%E3%81%99%E3%82%8B%E3%82%A2%E3%83%97%E3%83%AA%E3%81%AE%E6%89%BF%E8%AA%8D%E3%82%92%E7%AE%A1%E7%90%86%E3%81%99%E3%82%8B

### 2.通知するSlackチャンネルのインテグレーションに追加する。
![](/images/alert/slack_add_1.png)
- 筆者の環境では、既に複数アプリケーションを追加しているため、画像の内容が厳密に同じである必要はないです。
![](/images/alert/slack_add_2.png)
![](/images/alert/slack_add_3.png)
&nbsp;

## コード
### Budget
- 月額`30$`を予算とし、アラートを発砲する閾値を`2$`,`10$`,`20$`,`30$`で設定。
- アラートの通知先は、SNSに設定。

```hcl:budget.tf
locals {
  monthly_budget = {
    test   = 2  # ブログの画像用に少額で設定。
    low    = 10
    middle = 20
    high   = 30
  }
}

resource "aws_budgets_budget" "notify_slack" {
  name              = "monthly-budget"
  budget_type       = "COST"
  limit_amount      = 30 # 予算値を30$に設定
  limit_unit        = "USD"
  time_period_start = "2024-08-01_00:00" # 適用開始をブログに掲載している年月へ設定
  time_unit         = "MONTHLY"

  cost_types {
    include_tax     = true # デフォルトでtrueだが、コードを見れば分かるよう明示的に記載している
    include_support = true
  }

  # SNS通知の設定
  # 最小のコード量で済むよう、dynamicブロック使用。
  dynamic "notification" {
    for_each = { for k, v in local.monthly_budget : k => v }
    content {
      comparison_operator = "GREATER_THAN"
      notification_type   = "ACTUAL"
      threshold           = notification.value
      threshold_type      = "ABSOLUTE_VALUE"
      subscriber_sns_topic_arns = [aws_sns_topic.slack_alert.arn]
    }
  }
}
```
https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/budgets_budget

### SNS
:::message
- `us-east-1`リージョンに設定すること。
- SNSトピックポリシーで`budgets.amazonaws.com`にSNSをパブリッシュする権限を付与する必要がある。
:::


```hcl:sns.tf
resource "aws_sns_topic" "slack_alert" {
  name     = "slack-alert"
  provider = aws.us-east-1
}

resource "aws_sns_topic_policy" "slack_alert" {
  arn = aws_sns_topic.slack_alert.arn
  provider = aws.us-east-1
  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Service = "budgets.amazonaws.com"
        },
        Action = "SNS:Publish",
        Resource = aws_sns_topic.slack_alert.arn,
        Condition = {
          StringEquals = {
            "aws:SourceAccount" = data.aws_caller_identity.self.account_id
          }
        }
      }
    ]
  })
}
```
https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy

### Chatbot
- Chatbotの権限は、ガードレールポリシーの範囲内でIAMロールで設定した権限を行使する事が出来る。

```hcl:chatbot.tf
locals {
  chatbots = {
    my_account = {
      name               = "budget-alert-notify"
      slack_workspace_id = "{通知したいSlackのワークスペースIDを記載}"
      slack_channel_id   = "{通知したいSlackチャンネルIDを記載}"
    }
  }
}

resource "awscc_chatbot_slack_channel_configuration" "notify_slack" {
  for_each           = { for k, v in local.chatbots : k => v }
  configuration_name = each.key
  iam_role_arn       = aws_iam_role.chatbot.arn
  guardrail_policies = [
    "arn:aws:iam::aws:policy/ReadOnlyAccess",
  ]
  slack_channel_id   = each.value.slack_channel_id
  slack_workspace_id = each.value.slack_workspace_id
  logging_level      = "ERROR"
  sns_topic_arns     = [aws_sns_topic.slack_alert.arn]
  user_role_required = true

  tags = [
    {
      key   = "Name"
      value = each.key
    }
  ]
}
```

https://registry.terraform.io/providers/hashicorp/awscc/latest/docs/resources/chatbot_slack_channel_configuration

- Chatbotに設定するIAMロール
```hcl:iam.tf
resource "aws_iam_role" "chatbot" {
  name                  = "AWSChatbot-role"
  description           = "AWS Chatbot Execution Role"
  path                  = "/service-role/"
  force_detach_policies = false
  max_session_duration  = 3600

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "chatbot.amazonaws.com"
        }
      }
    ]
  })
}

# 想定外のエラーにならないよう、デフォルトのテンプレートポリシーに沿った設定しているためワイルドーカードで定義している。
#tfsec:ignore:aws-iam-no-policy-wildcards
data "aws_iam_policy_document" "chatbot" {
  statement {
    actions = [
      "cloudwatch:Describe*",
      "cloudwatch:Get*",
      "cloudwatch:List*"
    ]
    effect    = "Allow"
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "chatbot" {
  name   = aws_iam_role.chatbot.name
  role   = aws_iam_role.chatbot.name
  policy = data.aws_iam_policy_document.chatbot.json
}
```

&nbsp;
## SlackワークスペースとChatbotの関連付け
### 1.AWSマネジメントコンソール画面でChatbotの画面へ遷移
![](/images/alert/chatbot_console_0.png)

### 2.設定済みクライアントを選択し、以下画像の流れで関連付けを行う。
![](/images/alert/chatbot_console_1.png)

![](/images/alert/chatbot_console_2.png)

### ※注意
:::message alert
上記コンソール画面での設定を行わないと、terraform apply時に以下エラーが発生する。
:::

```shell:エラーメッセージ
Error: AWS SDK Go Service Operation Incomplete
Waiting for Cloud Control API service CreateResource operation completion returned: waiter state transitioned to FAILED. StatusMessage:
# 以下省略
```
