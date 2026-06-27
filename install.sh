#!/bin/bash
# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  CodeFarol — Instalador Automático v2                                      ║
# ║  Não navegue sozinho.                                                      ║
# ║                                                                            ║
# ║  Uso:                                                                      ║
# ║  curl -sSL https://raw.githubusercontent.com/rtenorioh/CodeFarol/          ║
# ║       main/infra/scripts/install.sh | sudo bash -s                         ║
# ║       <DOMAIN> <GITHUB_CLIENT_ID> <GITHUB_CLIENT_SECRET>                   ║
# ║       <RESEND_API_KEY> <ADMIN_EMAIL> <ADMIN_GITHUB_USERNAME>               ║
# ╚════════════════════════════════════════════════════════════════════════════╝

set -euo pipefail

# ── Cores ────────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

# ── Validação de argumentos ──────────────────────────────────────────────────
if [ "$#" -ne 6 ]; then
  echo -e "${RED}Erro: número incorreto de argumentos.${NC}"
  echo ""
  echo "Uso:"
  echo "  curl -sSL https://raw.githubusercontent.com/rtenorioh/CodeFarol/main/infra/scripts/install.sh | sudo bash -s \\"
  echo "    <DOMAIN> <GITHUB_CLIENT_ID> <GITHUB_CLIENT_SECRET> \\"
  echo "    <RESEND_API_KEY> <ADMIN_EMAIL> <ADMIN_GITHUB_USERNAME>"
  echo ""
  echo "Argumentos:"
  echo "  DOMAIN                  Domínio (ex: codefarol.dev)"
  echo "  GITHUB_CLIENT_ID        Client ID do GitHub OAuth App"
  echo "  GITHUB_CLIENT_SECRET    Client Secret do GitHub OAuth App"
  echo "  RESEND_API_KEY          API Key do Resend"
  echo "  ADMIN_EMAIL             E-mail do admin"
  echo "  ADMIN_GITHUB_USERNAME   Username do GitHub do admin inicial (ex: rtenorioh)"
  echo ""
  echo "Senhas de banco, JWT e chaves de encriptação são geradas automaticamente."
  exit 1
fi

DOMAIN="$1"
GITHUB_CLIENT_ID="$2"
GITHUB_CLIENT_SECRET="$3"
RESEND_API_KEY="$4"
ADMIN_EMAIL="$5"
ADMIN_GITHUB_USERNAME="$6"

# ── Verificações ─────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo -e "${RED}Erro: execute como root (sudo).${NC}"
  exit 1
fi

# ── Sistema de log ───────────────────────────────────────────────────────────
LOG_DIR="/home/deploy/logs"
LOG_TYPE="install"
TIMESTAMP=$(date +%Y-%m-%d_%H%M%S)
LOG_FILE="$LOG_DIR/$LOG_TYPE/${TIMESTAMP}_${LOG_TYPE}.log"
START_TIME=$(date +%s)

mkdir -p "$LOG_DIR/install" "$LOG_DIR/upgrade" "$LOG_DIR/backup"
chown -R deploy:deploy "$LOG_DIR" 2>/dev/null || true

log() {
  local level="$1"
  shift
  local message="$*"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  local line="[$timestamp] [$level] $message"

  echo "$line" >> "$LOG_FILE"

  case "$level" in
    INFO)  echo -e "${GREEN}$line${NC}" ;;
    WARN)  echo -e "${YELLOW}$line${NC}" ;;
    ERROR) echo -e "${RED}$line${NC}" ;;
    OK)    echo -e "${GREEN}  ✓ $message${NC}" ;;
    *)     echo "$line" ;;
  esac
}

step() {
  local num="$1"
  local total="$2"
  shift 2
  local desc="$*"
  log "INFO" "[$num/$total] $desc"
}

log_summary() {
  local end_time
  end_time=$(date +%s)
  local duration=$((end_time - START_TIME))
  local minutes=$((duration / 60))
  local seconds=$((duration % 60))

  log "INFO" "════════════════════════════════════════════"
  log "INFO" "Execução concluída em ${minutes}m${seconds}s"
  log "INFO" "Log salvo em: $LOG_FILE"
  log "INFO" "════════════════════════════════════════════"
}

# ── Banner ───────────────────────────────────────────────────────────────────
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  ${BOLD}CodeFarol — Instalador Automático${NC}${CYAN}         ║${NC}"
echo -e "${CYAN}║  Não navegue sozinho.                      ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"

log "INFO" "Instalação iniciada para domínio: $DOMAIN"
log "INFO" "E-mail admin: $ADMIN_EMAIL"
log "INFO" "GitHub username admin: $ADMIN_GITHUB_USERNAME"

# ── Etapa 1: Atualizar sistema ───────────────────────────────────────────────
step 1 10 "Atualizando sistema..."
apt-get update -qq >> "$LOG_FILE" 2>&1
apt-get upgrade -y -qq >> "$LOG_FILE" 2>&1
log "OK" "Sistema atualizado"

# ── Etapa 2: Dependências ───────────────────────────────────────────────────
step 2 10 "Instalando dependências..."
apt-get install -y -qq curl git ufw openssl >> "$LOG_FILE" 2>&1
log "OK" "Dependências instaladas"

# ── Etapa 3: Usuário deploy ─────────────────────────────────────────────────
step 3 10 "Configurando usuário 'deploy'..."
if id "deploy" &>/dev/null; then
  log "WARN" "Usuário 'deploy' já existe — mantendo senha atual"
  DEPLOY_PASSWORD="(usuário já existia — senha não foi alterada pelo instalador)"
else
  echo ""
  echo -e "${YELLOW}Defina a senha do usuário 'deploy' (login SSH e sudo):${NC}"
  read -r -s -p "Senha: " DEPLOY_PASSWORD < /dev/tty
  echo ""
  read -r -s -p "Confirme a senha: " DEPLOY_PASSWORD_CONFIRM < /dev/tty
  echo ""

  if [ -z "$DEPLOY_PASSWORD" ]; then
    log "ERROR" "Senha não pode ser vazia. Execute o instalador novamente."
    exit 1
  fi
  if [ "$DEPLOY_PASSWORD" != "$DEPLOY_PASSWORD_CONFIRM" ]; then
    log "ERROR" "As senhas não coincidem. Execute o instalador novamente."
    exit 1
  fi

  useradd -m -s /bin/bash deploy
  echo "deploy:$DEPLOY_PASSWORD" | chpasswd
  usermod -aG sudo deploy
  log "OK" "Usuário 'deploy' criado"
fi

# ── Etapa 4: Docker ─────────────────────────────────────────────────────────
step 4 10 "Instalando Docker..."
if command -v docker &>/dev/null; then
  log "WARN" "Docker já instalado — pulando"
else
  curl -fsSL https://get.docker.com | sh >> "$LOG_FILE" 2>&1
  log "OK" "Docker instalado"
fi
usermod -aG docker deploy

# ── Etapa 5: Firewall ───────────────────────────────────────────────────────
step 5 10 "Configurando firewall..."
ufw allow OpenSSH >> "$LOG_FILE" 2>&1
ufw allow 80/tcp >> "$LOG_FILE" 2>&1
ufw allow 443/tcp >> "$LOG_FILE" 2>&1
echo "y" | ufw enable >> "$LOG_FILE" 2>&1
log "OK" "UFW ativo (SSH, 80, 443)"

# ── Etapa 6: Clone ──────────────────────────────────────────────────────────
step 6 10 "Clonando CodeFarol..."
INSTALL_DIR="/home/deploy/CodeFarol"

# Repositório é privado — precisa de uma deploy key SSH já cadastrada para o
# usuário 'deploy' ANTES de rodar o instalador. Sem essa checagem, um clone
# via HTTPS sem credenciais ficaria pendurado num prompt de senha que nunca
# seria aceito (GitHub não autentica mais git por senha de conta).
SSH_CHECK_OUTPUT=$(sudo -u deploy ssh -o StrictHostKeyChecking=accept-new -o BatchMode=yes -T git@github.com </dev/null 2>&1) || true
echo "$SSH_CHECK_OUTPUT" >> "$LOG_FILE"
if ! echo "$SSH_CHECK_OUTPUT" | grep -q "successfully authenticated"; then
  log "ERROR" "Usuário 'deploy' não tem acesso SSH ao repositório privado."
  log "ERROR" "Saída real do teste SSH:"
  while IFS= read -r line; do log "ERROR" "  $line"; done <<< "$SSH_CHECK_OUTPUT"
  log "ERROR" "Se a saída acima estiver vazia ou diferente do esperado, configure a deploy key:"
  log "ERROR" "  sudo -u deploy ssh-keygen -t ed25519 -f /home/deploy/.ssh/id_ed25519 -N \"\""
  log "ERROR" "  sudo -u deploy cat /home/deploy/.ssh/id_ed25519.pub"
  log "ERROR" "  Cadastre em: github.com/rtenorioh/CodeFarol/settings/keys"
  exit 1
fi

if [ -d "$INSTALL_DIR" ]; then
  cd "$INSTALL_DIR"
  sudo -u deploy git pull origin main </dev/null >> "$LOG_FILE" 2>&1
  log "WARN" "Repositório já existia — atualizado via git pull"
else
  sudo -u deploy git clone git@github.com:rtenorioh/CodeFarol.git "$INSTALL_DIR" </dev/null >> "$LOG_FILE" 2>&1
  cd "$INSTALL_DIR"
  log "OK" "Repositório clonado"
fi

# ── Etapa 7: Gerar secrets + .env.production ─────────────────────────────────
step 7 10 "Gerando secrets e criando .env.production..."

DB_PASSWORD=$(openssl rand -hex 16)
JWT_SECRET=$(openssl rand -base64 48)
SETTINGS_ENCRYPTION_KEY=$(openssl rand -hex 32)
REDIS_PASSWORD=$(openssl rand -hex 16)

install -o deploy -g deploy -m 600 /dev/null "$INSTALL_DIR/.env.production"
cat > "$INSTALL_DIR/.env.production" <<ENVFILE
# ╔════════════════════════════════════════════════════════════════════════════╗
# ║  CodeFarol — Variáveis de Produção                                         ║
# ║  Gerado automaticamente em $(date +%Y-%m-%d\ %H:%M:%S)                     ║
# ║  Secrets internos gerados pelo instalador — NÃO alterar.                   ║
# ╚════════════════════════════════════════════════════════════════════════════╝

# ── Database (gerado automaticamente) ────────────────────────────────────────
DB_USER=codefarol
DB_PASSWORD=${DB_PASSWORD}
DB_NAME=codefarol
DATABASE_URL=postgresql://codefarol:${DB_PASSWORD}@db:5432/codefarol?schema=public

# ── Redis (gerado automaticamente) ───────────────────────────────────────────
REDIS_PASSWORD=${REDIS_PASSWORD}
REDIS_URL=redis://:${REDIS_PASSWORD}@redis:6379

# ── JWT (gerado automaticamente) ─────────────────────────────────────────────
JWT_SECRET=${JWT_SECRET}
JWT_ACCESS_EXPIRES_IN=15m
JWT_REFRESH_EXPIRES_IN=7d

# ── App ──────────────────────────────────────────────────────────────────────
NODE_ENV=production
PORT=3000
FRONTEND_URL=https://${DOMAIN}
API_URL=https://${DOMAIN}
CORS_ORIGINS=https://${DOMAIN},https://www.${DOMAIN}

# ── GitHub OAuth ─────────────────────────────────────────────────────────────
GITHUB_CLIENT_ID=${GITHUB_CLIENT_ID}
GITHUB_CLIENT_SECRET=${GITHUB_CLIENT_SECRET}
GITHUB_CALLBACK_URL=https://${DOMAIN}/v1/auth/github/callback
ADMIN_GITHUB_USERNAME=${ADMIN_GITHUB_USERNAME}

# ── Resend ───────────────────────────────────────────────────────────────────
RESEND_API_KEY=${RESEND_API_KEY}
RESEND_FROM=CodeFarol <noreply@${DOMAIN}>

# ── Encryption (gerado automaticamente) ──────────────────────────────────────
SETTINGS_ENCRYPTION_KEY=${SETTINGS_ENCRYPTION_KEY}

# ── Sentry (preencher após criar projetos em sentry.io) ─────────────────────
SENTRY_DSN=
VITE_SENTRY_DSN=
ENVFILE

chmod 600 "$INSTALL_DIR/.env.production"
chown deploy:deploy "$INSTALL_DIR/.env.production"

log "OK" "JWT_SECRET gerado (64 chars base64)"
log "OK" "DB_PASSWORD gerado (32 chars base64)"
log "OK" "SETTINGS_ENCRYPTION_KEY gerado (32 bytes hex)"
log "OK" "REDIS_PASSWORD gerado (32 chars base64)"
log "OK" ".env.production criado (permissão 600)"

# ── Etapa 8: Certificado HTTPS ───────────────────────────────────────────────
step 8 10 "Obtendo certificado HTTPS..."

sed -i "s/codefarol.dev/${DOMAIN}/g" "$INSTALL_DIR/infra/nginx/conf.d/codefarol.conf"
sed -i "s/codefarol.dev/${DOMAIN}/g" "$INSTALL_DIR/infra/scripts/init-letsencrypt.sh"
sed -i "s/admin@codefarol.dev/${ADMIN_EMAIL}/g" "$INSTALL_DIR/infra/scripts/init-letsencrypt.sh"

chmod +x "$INSTALL_DIR/infra/scripts/init-letsencrypt.sh"

if bash "$INSTALL_DIR/infra/scripts/init-letsencrypt.sh" >> "$LOG_FILE" 2>&1; then
  log "OK" "Certificado HTTPS obtido"
else
  log "WARN" "HTTPS falhou — verifique se o DNS já aponta para esta VPS"
  log "WARN" "Após corrigir DNS, execute: sudo bash $INSTALL_DIR/infra/scripts/init-letsencrypt.sh"
fi

# ── Etapa 9: Containers ─────────────────────────────────────────────────────
step 9 10 "Subindo containers..."
cd "$INSTALL_DIR"
docker compose --env-file .env.production -f docker-compose.prod.yml up -d --build >> "$LOG_FILE" 2>&1
log "INFO" "Aguardando containers ficarem prontos (20s)..."
sleep 20
log "OK" "Containers iniciados"

# ── Etapa 10: Migrations + Seed ──────────────────────────────────────────────
step 10 10 "Executando migrations e seed..."
docker compose -f docker-compose.prod.yml exec -T api npx prisma migrate deploy >> "$LOG_FILE" 2>&1
log "OK" "Migrations aplicadas"
docker compose -f docker-compose.prod.yml exec -T api npm run seed >> "$LOG_FILE" 2>&1
log "OK" "Seed executado"

# ── Backup automático ────────────────────────────────────────────────────────
log "INFO" "Configurando backup automático..."
chmod +x "$INSTALL_DIR/infra/scripts/backup.sh"
mkdir -p /home/deploy/backups/{daily,weekly,monthly}
chown -R deploy:deploy /home/deploy/backups
CRON_CMD="0 3 * * * $INSTALL_DIR/infra/scripts/backup.sh >> /home/deploy/logs/backup/backup.log 2>&1"
(sudo -u deploy crontab -l 2>/dev/null | grep -v "backup.sh"; echo "$CRON_CMD") | sudo -u deploy crontab -
log "OK" "Backup diário configurado (3h)"

# ── Health check ─────────────────────────────────────────────────────────────
log "INFO" "Verificando instalação..."
sleep 5

HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "http://localhost:3000/v1/health" 2>/dev/null || echo "000")
if [ "$HTTP_STATUS" = "200" ]; then
  log "OK" "Health check: API respondendo (200)"
else
  log "ERROR" "Health check falhou (status: $HTTP_STATUS)"
  log "ERROR" "Verifique: docker compose -f docker-compose.prod.yml logs api --tail=50"
fi

# ── Registrar versões ────────────────────────────────────────────────────────
log "INFO" "Versões instaladas:"
log "INFO" "  Docker: $(docker --version 2>/dev/null || echo 'N/A')"
log "INFO" "  Docker Compose: $(docker compose version 2>/dev/null || echo 'N/A')"
log "INFO" "  Git: $(git --version 2>/dev/null || echo 'N/A')"
log "INFO" "  OS: $(grep PRETTY_NAME /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '"' || echo 'N/A')"

# ── Salvar credenciais em arquivo protegido ──────────────────────────────────
CREDENTIALS_FILE="/home/deploy/.codefarol-credentials"
install -o deploy -g deploy -m 600 /dev/null "$CREDENTIALS_FILE"
cat > "$CREDENTIALS_FILE" <<CREDS
# CodeFarol — Credenciais geradas em $(date +%Y-%m-%d\ %H:%M:%S)
# GUARDE ESTE ARQUIVO EM LOCAL SEGURO E DELETE DA VPS APÓS COPIAR
DEPLOY_USER=deploy
DEPLOY_PASSWORD=${DEPLOY_PASSWORD}
DOMAIN=${DOMAIN}
DB_PASSWORD=${DB_PASSWORD}
CREDS
chmod 600 "$CREDENTIALS_FILE"
chown deploy:deploy "$CREDENTIALS_FILE"

# ── Resumo final ─────────────────────────────────────────────────────────────
log_summary

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  ${BOLD}Instalação concluída!${NC}${CYAN}                                    ║${NC}"
echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC}  URL:        https://${DOMAIN}                              ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  API health: https://${DOMAIN}/v1/health                    ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  Usuário:    deploy                                         ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  Projeto:    ${INSTALL_DIR}                                 ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  Backups:    /home/deploy/backups/ (diário às 3h)           ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  Logs:       /home/deploy/logs/                             ${CYAN}║${NC}"
echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC}  ${BOLD}Credenciais salvas em:${NC}                                    ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  ${CREDENTIALS_FILE}                                        ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  ${YELLOW}⚠ Copie para local seguro e delete da VPS!${NC}               ${CYAN}║${NC}"
echo -e "${CYAN}╠════════════════════════════════════════════════════════════╣${NC}"
echo -e "${CYAN}║${NC}  ${BOLD}Próximos passos:${NC}                                          ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  1. Copiar credenciais: scp deploy@IP:~/.codefarol-*  .    ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  2. Configurar SPF/DKIM/DMARC (docs/dns-email-setup.md)    ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  3. Criar projetos no Sentry → preencher DSNs              ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  4. Configurar Asaas via /admin/settings                    ${CYAN}║${NC}"
echo -e "${CYAN}║${NC}  5. Configurar UptimeRobot (docs/uptimerobot-setup.md)      ${CYAN}║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"