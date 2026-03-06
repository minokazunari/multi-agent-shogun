# 戦況ダッシュボード

最終更新: 2026-03-06 09:59 (家老)

## 🐸 Frog / ストリーク
| 項目 | 値 |
|------|-----|
| 今日のFrog | — |
| Frog状態 | — |
| ストリーク | — |
| 今日の完了 | 0/3 |

## 🔄 進行中

| cmd | 内容 | 担当 | 状態 |
|-----|------|------|------|
| cmd_182 | status更新手順追記+sync cron設定+cmd_180 status更新 | 足軽1/2/3並列 | 作業中 |
| cmd_181 | D2_mail_crawl本番SF未登録原因調査 | 足軽1完了+足軽2blocked | 殿判断待ち |

## ✅ 完了

| cmd | 内容 | 完了時刻 |
|-----|------|----------|
| cmd_180 | upstream/mainマージ+大将軍カスタマイズ保持+cmd_178/179統合（git push完了） | 2026-03-05 16:33 |
| cmd_179 | 家老→将軍inbox禁止撤廃+完了報告フロー整備 | 2026-03-05 16:22 |
| cmd_178 | daishogun_start.sh SSHフォールバック+sync_dashboard.sh scp同期追加 | 2026-03-05 16:16 |

## 🚨 要対応

### 本番サーバーSSH接続不可（cmd_181）

**状況**: LinuxマシンのIP(43.226.6.160)から本番サーバー(52.192.201.13)へのSSH接続がタイムアウト。AWSセキュリティグループで遮断されている模様。Mac(192.168.0.123)への接続もLAN外のため不可。

**コード分析結果（足軽1号完了）**:
- SalesForceApi.php: 新ContactMedia ID 2件追加済み（一般法人・日本電子）→ return null（感謝メール除外）
- 新mediaはSITE8(place=8)経由、getContactMedia()でsales_force_ad_mediaテーブルからfrom_addressキーで動的取得
- コードロジック自体に問題なし。**原因はDB側の可能性が高い**:
  - sales_force_ad_mediaテーブルにid 5,6+from_addressが正しく登録されているか
  - sales_force_exportsにmail_subjectパターンが登録されているか
  - そもそも本番にデプロイ(git pull)済みか

**殿への選択肢**:
- A) 殿が直接本番SSHして調査（推奨。コマンドはashigaru2_report.yaml参照）
- B) AWSセキュリティグループにLinux IP(43.226.6.160)を追加→家老側で調査続行
- C) Mac(daishogun)経由でSSH実行
