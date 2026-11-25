#!/bin/bash
# 自建 ASR 一键部署（华为云 113.44.186.159 / asr.cai8.com.cn）——可重复粘贴，幂等
set -x
SUDO=""; [ "$(id -u)" != "0" ] && SUDO="sudo"
TOKEN=$(head -c 24 /dev/urandom | od -An -tx1 | tr -d " \n")
if [ "$(id -u)" = "0" ]; then RUNAS() { runuser -u asr -- "$@"; }; else RUNAS() { sudo -u asr "$@"; }; fi
# 1) 系统包：python/ffmpeg/nginx/certbot（apt 或 yum 系自动识别）
if command -v apt-get >/dev/null; then
  $SUDO apt-get update -y
  $SUDO apt-get install -y ffmpeg nginx certbot python3-certbot-nginx curl
else
  $SUDO yum install -y ffmpeg nginx certbot python3-certbot-nginx curl || $SUDO dnf install -y ffmpeg nginx certbot python3-certbot-nginx curl
fi
# 2) 找一个 >=3.9 的 Python（faster-whisper 的要求）
PY=""
for c in python3.12 python3.11 python3.10 python3.9 python3; do
  if command -v $c >/dev/null && $c -c 'import sys; exit(0 if sys.version_info>=(3,9) else 1)' 2>/dev/null; then PY=$c; break; fi
done
if [ -z "$PY" ] && command -v apt-get >/dev/null; then
  $SUDO apt-get install -y python3.11 python3.11-venv || $SUDO apt-get install -y python3.10 python3.10-venv
  for c in python3.11 python3.10; do command -v $c >/dev/null && PY=$c && break; done
fi
if [ -z "$PY" ]; then echo "ASR-DEPLOY-FAIL: 没有 Python 3.9+，把这段输出发给我"; exit 1; fi
$PY -m venv --help >/dev/null 2>&1 || $SUDO apt-get install -y $PY-venv python3-venv
echo "Using $PY"
# 3) 程序与环境（独立目录 /opt/asr，不碰 fixdesk-db）
$SUDO mkdir -p /opt/asr
$SUDO useradd -r -d /opt/asr asr 2>/dev/null || true
echo IyDoh6rlu7ogQVNSIOi9rOWGmeacjeWKoe+8iGZhc3Rlci13aGlzcGVy77yJ77yaT3BlbkFJIOWFvOWuuSBQT1NUIC88VE9LRU4+L2F1ZGlvL3RyYW5zY3JpcHRpb25zIC0+IHsidGV4dCI6IC4uLn0KIyDpg6jnvbLlnKjmspnnm5LkuLvmnLogL2RhdGEvYXNyL++8jHN5c3RlbWQg5Y2V5YWDIGFzci5zZXJ2aWNlIOaJmOeuoe+8m+aXoOWklumDqCBLZXnvvIzpnaAgVVJMIOi3r+W+hOS7pOeJjOmYsua7peeUqOOAggppbXBvcnQgb3MsIHN1YnByb2Nlc3MsIHRocmVhZGluZwppbXBvcnQgbnVtcHkgYXMgbnAKZnJvbSBmbGFzayBpbXBvcnQgRmxhc2ssIHJlcXVlc3QsIGpzb25pZnksIGFib3J0CmZyb20gZmFzdGVyX3doaXNwZXIgaW1wb3J0IFdoaXNwZXJNb2RlbAoKVE9LRU4gPSBvcy5lbnZpcm9uWyJBU1JfVE9LRU4iXQpNT0RFTF9OQU1FID0gb3MuZW52aXJvbi5nZXQoIkFTUl9NT0RFTCIsICJzbWFsbCIpClBPUlQgPSBpbnQob3MuZW52aXJvbi5nZXQoIkFTUl9QT1JUIiwgIjg5MzQiKSkKCmFwcCA9IEZsYXNrKF9fbmFtZV9fKQptb2RlbCA9IFdoaXNwZXJNb2RlbChNT0RFTF9OQU1FLCBkZXZpY2U9ImNwdSIsIGNvbXB1dGVfdHlwZT0iaW50OCIsCiAgICAgICAgICAgICAgICAgICAgIGRvd25sb2FkX3Jvb3Q9b3MucGF0aC5qb2luKG9zLnBhdGguZGlybmFtZShvcy5wYXRoLmFic3BhdGgoX19maWxlX18pKSwgIm1vZGVscyIpLCBjcHVfdGhyZWFkcz00LCBudW1fd29ya2Vycz0xKQpsb2NrID0gdGhyZWFkaW5nLkxvY2soKSAgIyDljZXmnaHkuLLooYzmjqjnkIbvvIzpgb/lhY3lpJror7fmsYLmiqIgNCDmoLgKCkBhcHAuZ2V0KGYiL3tUT0tFTn0vaGVhbHRoIikKZGVmIGhlYWx0aCgpOgogICAgcmV0dXJuIGpzb25pZnkob2s9VHJ1ZSwgbW9kZWw9TU9ERUxfTkFNRSkKCkBhcHAucG9zdChmIi97VE9LRU59L2F1ZGlvL3RyYW5zY3JpcHRpb25zIikKZGVmIHRyYW5zY3JpcHRpb25zKCk6CiAgICBmID0gcmVxdWVzdC5maWxlcy5nZXQoImZpbGUiKQogICAgaWYgbm90IGY6CiAgICAgICAgYWJvcnQoNDAwLCAibWlzc2luZyBmaWxlIikKICAgIGRhdGEgPSBmLnJlYWQoKQogICAgaWYgbGVuKGRhdGEpID4gOCAqIDEwMjQgKiAxMDI0OgogICAgICAgIGFib3J0KDQxMywgInRvbyBsYXJnZSIpCiAgICBpZiBsZW4oZGF0YSkgPCAyMDA6CiAgICAgICAgYWJvcnQoNDAwLCAiZW1wdHkgYXVkaW8iKQogICAgbGFuZyA9IHJlcXVlc3QuZm9ybS5nZXQoImxhbmd1YWdlIikgb3IgTm9uZQogICAgIyDnlKjns7vnu58gZmZtcGVnIOino+eggeaIkCAxNmtIeiDljZXlo7DpgZPms6LlvaLlkI7lloIgbmRhcnJhee+8jOe7leW8gCBQeUFWIOeJiOacrOWFvOWuuemXrumimAogICAgcCA9IHN1YnByb2Nlc3MucnVuKFsiZmZtcGVnIiwgIi12IiwgImVycm9yIiwgIi1pIiwgInBpcGU6MCIsICItZiIsICJmMzJsZSIsICItYXIiLCAiMTYwMDAiLCAiLWFjIiwgIjEiLCAicGlwZToxIl0sCiAgICAgICAgICAgICAgICAgICAgICAgaW5wdXQ9ZGF0YSwgY2FwdHVyZV9vdXRwdXQ9VHJ1ZSkKICAgIGlmIHAucmV0dXJuY29kZSAhPSAwIG9yIG5vdCBwLnN0ZG91dDoKICAgICAgICBhYm9ydCg0MDAsICJhdWRpbyBkZWNvZGUgZmFpbGVkIikKICAgIHdhdmUgPSBucC5mcm9tYnVmZmVyKHAuc3Rkb3V0LCBkdHlwZT1ucC5mbG9hdDMyKQogICAgd2l0aCBsb2NrOgogICAgICAgIHNlZ21lbnRzLCBfaW5mbyA9IG1vZGVsLnRyYW5zY3JpYmUod2F2ZSwgbGFuZ3VhZ2U9bGFuZywgYmVhbV9zaXplPTEsIHZhZF9maWx0ZXI9VHJ1ZSkKICAgICAgICB0ZXh0ID0gIiIuam9pbihzLnRleHQgZm9yIHMgaW4gc2VnbWVudHMpLnN0cmlwKCkKICAgIHJldHVybiBqc29uaWZ5KHRleHQ9dGV4dCkKCmlmIF9fbmFtZV9fID09ICJfX21haW5fXyI6CiAgICBhcHAucnVuKGhvc3Q9b3MuZW52aXJvbi5nZXQoIkFTUl9IT1NUIiwgIjAuMC4wLjAiKSwgcG9ydD1QT1JULCB0aHJlYWRlZD1UcnVlKQo= | base64 -d | $SUDO tee /opt/asr/server.py >/dev/null
$SUDO tee /opt/asr/asr.env >/dev/null <<EOF2
ASR_TOKEN=$TOKEN
ASR_MODEL=/opt/asr/model-small
ASR_PORT=8934
ASR_HOST=127.0.0.1
HF_ENDPOINT=https://hf-mirror.com
EOF2
$SUDO chown -R asr:asr /opt/asr 2>/dev/null || $SUDO chown -R asr /opt/asr
# 4) venv + 依赖（腾讯云 PyPI 镜像）+ 预下载模型（HF 镜像）
if command -v apt-get >/dev/null; then $SUDO apt-get install -y ${PY}-venv python3-venv 2>/dev/null || true; fi
$SUDO rm -rf /opt/asr/venv
RUNAS $PY -m venv /opt/asr/venv
[ -x /opt/asr/venv/bin/pip ] || RUNAS /opt/asr/venv/bin/python -m ensurepip --default-pip || { echo "ASR-DEPLOY-FAIL: venv 里没有 pip（ensurepip 缺失），把输出发给我"; exit 1; }
RUNAS /opt/asr/venv/bin/pip install -q -i https://mirrors.cloud.tencent.com/pypi/simple --upgrade pip || true
RUNAS /opt/asr/venv/bin/pip install -q -i https://mirrors.cloud.tencent.com/pypi/simple faster-whisper flask || { echo "ASR-DEPLOY-FAIL: pip 安装失败，把输出发给我"; exit 1; }
$SUDO mkdir -p /opt/asr/model-small && $SUDO chown -R asr:asr /opt/asr/model-small
for f in config.json model.bin tokenizer.json vocabulary.txt; do RUNAS curl -fSL -C - --retry 3 -o /opt/asr/model-small/$f https://modelscope.cn/models/pengzhendong/faster-whisper-small/resolve/master/$f || { echo "ASR-DEPLOY-FAIL: 模型文件 $f 下载失败，把输出发给我"; exit 1; }; done
RUNAS /opt/asr/venv/bin/python -c "from faster_whisper import WhisperModel; WhisperModel('/opt/asr/model-small', device='cpu', compute_type='int8'); print('MODEL-READY')" || { echo "ASR-DEPLOY-FAIL: 模型加载失败，把输出发给我"; exit 1; }
# 5) systemd 托管（带资源上限：内存 1.2G、CPU 250%、低优先级，保护同机数据库）
$SUDO tee /etc/systemd/system/asr.service >/dev/null <<EOF3
[Unit]
Description=Self-hosted ASR (faster-whisper)
After=network.target
[Service]
User=asr
EnvironmentFile=/opt/asr/asr.env
ExecStart=/opt/asr/venv/bin/python /opt/asr/server.py
Restart=always
RestartSec=3
MemoryMax=1200M
CPUQuota=250%
Nice=10
[Install]
WantedBy=multi-user.target
EOF3
$SUDO systemctl daemon-reload
$SUDO systemctl enable --now asr.service
sleep 12
curl -s http://127.0.0.1:8934/$TOKEN/health || { echo "ASR-DEPLOY-FAIL: 本地服务没起来，看 journalctl -u asr.service"; exit 1; }
# 6) nginx 反代 + Let's Encrypt 证书（需 DNS 已解析且防火墙放行 80/443）
$SUDO tee /etc/nginx/conf.d/asr.conf >/dev/null <<EOF4
server {
  listen 80;
  server_name asr.cai8.com.cn;
  client_max_body_size 10m;
  location / { proxy_pass http://127.0.0.1:8934; proxy_set_header Host $host; proxy_read_timeout 120s; }
}
EOF4
$SUDO nginx -t && $SUDO systemctl reload nginx || $SUDO systemctl restart nginx
$SUDO certbot --nginx -d asr.cai8.com.cn --non-interactive --agree-tos --register-unsafely-without-email --redirect || echo "ASR-CERT-WARN: 证书没签下来（多半是防火墙 80 没放行或 DNS 未生效），服务本地已跑，把输出发给我"
echo "ASR-TOKEN: $TOKEN"
curl -s https://asr.cai8.com.cn/$TOKEN/health && echo "" && echo "ASR-DEPLOY-OK" || echo "ASR-DEPLOY-CHECK: 公网 health 未通，把以上输出发给我"
