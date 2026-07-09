このファイルは、この repository で作業する Codex/agent 向けのルールです。
適用範囲は repository 全体です。

## 作業開始時

- `git status --short`、`TODO.md`、関連する `docs/`、直近の `git log --oneline` を確認する。
- 不明点はまず既存 docs、scripts、commit history、artifacts を確認する。

## プロジェクト方針

このプロジェクトではPOWKIDDY V90Sというハンドヘルドで動作するLinuxを構築することが目的になります。
作業履歴、ログはgitを使って進めましょう。

# 要望
## Linuxディストリビューションについて
armbianを利用してV90Sで動作するLinuxを作りたい

## V90SのLinuxカーネルについて
V90SのカーネルはクローズドソースなのでKNULLIのビルド方法を参考にarmbianで動作する方法を模索したい
https://knulli.org/ja/development/building-knulli-with-docker/

## ステップ1の目標
V90S実機でブートするSDカードイメージを生成し、画面にコンソールが表示され、USBキーボードで文字入力ができ、lsコマンドなどが実行できるところまで進めたい

# 計画
- まずは上記要望を叶えるための情報収集を行う
- armbianをビルドする環境を作成する
- SDカードイメージを生成する仕組みを構築する
- 実機動作確認は私の方で実施します
