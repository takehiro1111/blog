---
title: "Terraformを使ったECS停止時のカスタムSlack通知の実装"
emoji: "😎"
type: "tech" # tech: 技術記事 / idea: アイデア
topics: ["AWS","EventBridge","ECS","Chatbot","Terraform"]
published: true
---
![](/images/event_bridge/amazon-eventbridge-960x504-1.png =500x)


## 1.記事を書いた理由
- 業務でECSの異常停止時にSlackへ通知する仕組みを導入していますが、デフォルトの通知内容だと見辛く、エラーコードや停止理由の確認がAWSコンソールに慣れていない人には難しいという課題がありました

## 2.構成
- 何らかの理由でECSが停止した際にEventBridgeで設定したルールでキャッチし、SNS,Chatbot経由でSlackへ通知する構成です。
- Lambdaでも実現出来るかと思いますが、今回は細かい要件を想定しておらず運用工数的にもChatbotで良い感じに通知してくれる構成にしています。
- クラスメソッドさんの記事を大変参考にさせていただきました。
https://dev.classmethod.jp/articles/ecs-task-stop-reason-slack-notification/
![](/images/event_bridge/ecs_stop_event_notify.png)

### デフォルトの通知内容
  - ECSが停止したことは分かるのですが、この通知内容だとエラーコトードや停止理由が一目で分からず、すぐに現状把握することが出来ません。
![](/images/event_bridge/default_notify.png)

### 今回設定するカスタマイズの通知イメージ
  - 停止コードや理由の記載により、デフォルトの通知内容と比較して現状把握しやすくなったと思います。
  - 細かい通知項目やUIはお好みでカスタマイズして下さい。
![](/images/event_bridge/customize_notify.png)

## 3.各サービスのコード
### 前提
- 本記事では`通知内容をカスタマイズしている点`に焦点を当てたいため、ECS含めたWebまでのアクセスに必要なリソース、IAM等のセキュリティ周りの記載は省略しています。

### ①EventBridge
- 停止理由のフィルターは行わず、ECSが停止した際に広くキャッチするようなルール設定にしています。
- `input_transformer`ブロックを使って停止時の詳細情報（例えば、停止理由やエラーコード）を通知に含めるようにしています。これにより、AWSコンソールを開かなくても情報を一目で確認できるようになりました。
- `ECS task state change`イベントの中身：https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ecs_task_events.html
- `DescribeTasks API`: https://docs.aws.amazon.com/AmazonECS/latest/APIReference/API_DescribeTasks.html
- カスタマイズの通知内容の実装：https://docs.aws.amazon.com/ja_jp/eventbridge/latest/userguide/eb-transform-target-input.html
- Chatbotのスキーマに合わせたテンプレート参考：https://docs.aws.amazon.com/chatbot/latest/adminguide/custom-notifs.html

```hcl
resource "aws_cloudwatch_event_rule" "ecs_event" {
  state       = "ENABLED"
  name        = "ecs-event-notify"
  description = "ecs alert notification rule"
  event_bus_name = "default"

  event_pattern = <<END
    {
      "source": ["aws.ecs"],
      "detail-type": [
        "ECS Task State Change"
      ],
      "detail": {
        "lastStatus": [
          "STOPPED"
        ],
        "clusterArn": [
          "${aws_ecs_cluster.web.arn}"
        ]
      }
    }
  END
}

resource "aws_cloudwatch_event_target" "ecs_event" {
  target_id = "ecs-event-notify"
  rule      = aws_cloudwatch_event_rule.ecs_event.name
  arn       = module.sns_notify_chatbot.topic_arn

  input_transformer {
    input_paths = {
      "account": "$.account",
      "availabilityZone": "$.detail.availabilityZone",
      "clusterArn": "$.detail.clusterArn",
      "group": "$.detail.group",
      "resource": "$.resources[0]",
      "stoppedAt": "$.detail.stoppedAt",
      "stopCode": "$.detail.stopCode",
      "stoppedReason": "$.detail.stoppedReason"
    }

    input_template = <<END
    {
      "version": "1.0",
      "source": "custom",
      "content": {
        "textType": "client-markdown",
        "title": ":warning: ECS のタスクが停止されました :warning:",
        "description": "overview\n・ACCOUNT_ID: `<account>`\n・AZ: `<availabilityZone>`\n ・Service:`<group>`\n・Task: `<resource>`\n・stoppedAt: `<stoppedAt>`\n・stopCode: `<stopCode>`\n・stoppedReason: `<stoppedReason>`"
      }
    }
    END
  }
}

```

### ②SNS
- EventBridgeのサービスエンドポイントがSNSを`Publish`出来るよう設定しています。
```hcl
// ref: https://github.com/terraform-aws-modules/terraform-aws-sns
module "sns_notify_chatbot" {
  source  = "terraform-aws-modules/sns/aws"
  version = "6.1.1"

  create = true
  name = "slack_notify"
  display_name = "slack_notify"

  create_topic_policy = false
  topic_policy = data.aws_iam_policy_document.sns_notify_chatbot.json
}

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "sns_notify_chatbot" {
  statement {
    sid = "AWSEvents_EcsEvent"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    actions = ["sns:Publish"]
    resources = [
      "arn:aws:sns:ap-northeast-1:${data.aws_caller_identity.current.account_id}:slack_notify"
    ]
  }
}
```


### ③Chatbot
- 個人環境で複数のChatbotを作成してしまっているため`for_each`を用いていますが、今回のケースは特に必要無いです。
```hcl
locals {
  chatbots = {
    personal = {
      name               = {お好きな名前を付与}
      slack_workspace_id = {SlackのワークスペースID}
      slack_channel_id   = {SlackのチャンネルID}
    }
  }
}

resource "awscc_chatbot_slack_channel_configuration" "example" {
  for_each           = { for k, v in local.chatbots : k => v }
  configuration_name = each.key
  iam_role_arn       = aws_iam_role.chatbot.arn // 今回IAMロールの設定の記載は焼灼しています。
  guardrail_policies = [
    "arn:aws:iam::aws:policy/AdministratorAccess"
  ]
  slack_channel_id   = each.value.slack_channel_id
  slack_workspace_id = each.value.slack_workspace_id
  logging_level      = "ERROR"
  sns_topic_arns     = [
    module.sns_notify_chatbot.topic_arn // 通知を受け取るSNSを指定。
  ]
  user_role_required = true

  tags = [{
    key   = "Name"
    value = each.key
  }]
}
```

## 4.最後に
- 通知内容をよりカスタマイズしたい場合はLambdaでも良いかと思いますが、ランタイムのバージョンアップ等の管理面が面倒なため、細かい要件がなければ今回のようにシンプルな構成でも良いと思います。
- 最後まで読んでくださりありがとうございました。
