#!/bin/bash

set -e

echo -e "\n📦 正在更新系统并安装依赖..."
apt-get update && apt install sudo -y
sudo apt install -y screen curl iptables build-essential git wget lz4 jq make gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip

echo -e "\n🦀 安装 Rust..."
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
source "$HOME/.cargo/env"
rustup default stable

echo -e "\n📁 检查 nockchain 仓库..."
if [ -d "nockchain" ]; then
  echo "⚠️ 已存在 nockchain 目录，是否删除重新克隆（必须选 y ）？(y/n)"
  read -r confirm
  if [[ "$confirm" == "y" || "$confirm" == "Y" ]]; then
    rm -rf nockchain
    git clone https://github.com/zorp-corp/nockchain
  else
    echo "➡️ 使用已有目录 nockchain"
  fi
else
  git clone https://github.com/zorp-corp/nockchain
fi

cd nockchain

echo -e "\n🔧 开始编译核心组件..."
make install-hoonc
make build
make install-nockchain-wallet
make install-nockchain

echo -e "\n✅ 编译完成，配置环境变量..."
echo 'export PATH="$PATH:/root/nockchain/target/release"' >> ~/.bashrc
echo 'export RUST_LOG=info' >> ~/.bashrc
echo 'export MINIMAL_LOG_FORMAT=true' >> ~/.bashrc
source ~/.bashrc
export CUDA_VISIBLE_DEVICES=""
export CPU_ONLY=true

# === 生成钱包 ===
echo -e "\n🔐 自动生成钱包助记词与主私钥..."
WALLET_CMD="./target/release/nockchain-wallet"
if [ ! -f "$WALLET_CMD" ]; then
  echo "❌ 未找到钱包命令 $WALLET_CMD"
  exit 1
fi

SEED_OUTPUT=$($WALLET_CMD keygen)
echo "$SEED_OUTPUT"

SEED_PHRASE=$(echo "$SEED_OUTPUT" | grep -iE "seed phrase" | sed 's/.*: //')
echo -e "\n🧠 助记词：$SEED_PHRASE"

echo -e "\n🔑 从助记词派生主私钥..."
MASTER_PRIVKEY=$($WALLET_CMD gen-master-privkey --seedphrase "$SEED_PHRASE" | grep -i "master private key" | awk '{print $NF}')
echo "主私钥：$MASTER_PRIVKEY"

echo -e "\n📬 获取主公钥..."
MASTER_PUBKEY=$($WALLET_CMD gen-master-pubkey --master-privkey "$MASTER_PRIVKEY" | grep -i "master public key" | awk '{print $NF}')
echo "主公钥：$MASTER_PUBKEY"

echo -e "\n💾 保存助记词和密钥到文件..."
{
  echo "=== Nockchain 钱包备份 ==="
  echo "生成时间: $(date)"
  echo "助记词: $SEED_PHRASE"
  echo "主私钥: $MASTER_PRIVKEY"
  echo "主公钥: $MASTER_PUBKEY"
} > "$HOME/nockchain_wallet_backup.txt"
chmod 600 "$HOME/nockchain_wallet_backup.txt"
echo "钱包备份已保存到: $HOME/nockchain_wallet_backup.txt"

echo -e "\n📄 写入 Makefile 挖矿公钥..."
sed -i "s|^export MINING_PUBKEY :=.*$|export MINING_PUBKEY := $MASTER_PUBKEY|" Makefile

# === 可选：初始化 choo hoon 测试 ===
read -p $'\n🌀 是否执行 choo 初始化测试？这一步可能卡住界面，非必须操作。输入 y 继续：' confirm_choo
if [[ "$confirm_choo" == "y" || "$confirm_choo" == "Y" ]]; then
  mkdir -p hoon assets
  echo "%trivial" > hoon/trivial.hoon
  choo --new --arbitrary hoon/trivial.hoon
fi

# === 启动指引 ===
echo -e "\n🚀 配置完成，启动命令如下："

echo -e "\n➡️ 启动 leader 节点："
echo -e "screen -S leader\nmake run-nockchain-leader"

echo -e "\n➡️ 启动 follower 节点："
echo -e "screen -S follower\nmake run-nockchain-follower"

echo -e "\n📄 查看日志方法："
echo -e "screen -r leader   # 查看 leader 日志"
echo -e "screen -r follower # 查看 follower 日志"
echo -e "Ctrl+A 再按 D 可退出 screen 会话"

echo -e "\n🔒 钱包备份位置："
echo -e "cat $HOME/nockchain_wallet_backup.txt"

echo -e "\n🎉 部署完成，祝你挖矿愉快！"
