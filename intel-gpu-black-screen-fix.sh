#!/bin/bash
# Script para desativar funções defeituosas de economia de energia da GPU Intel (UHD 610/620)
# Corrige o problema da tela preta repentina durante o uso ativo.

set -euo pipefail

echo "================================================="
echo " Correção da Tela Preta (GPU Intel) "
echo "================================================="
echo "Este script adiciona parâmetros ao GRUB para desativar:"
echo "1. Panel Self Refresh (PSR)"
echo "2. Framebuffer Compression (FBC)"
echo "-------------------------------------------------"

# Confere se os parâmetros já existem
if grep -q "i915.enable_psr=0" /etc/default/grub; then
    echo "[OK] Os parâmetros i915 já estão aplicados no GRUB."
    exit 0
fi

echo "Solicitando permissão para alterar o /etc/default/grub..."
# Adiciona os parâmetros na linha do GRUB_CMDLINE_LINUX_DEFAULT
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="\(.*\)"/GRUB_CMDLINE_LINUX_DEFAULT="\1 i915.enable_psr=0 i915.enable_fbc=0"/' /etc/default/grub

echo "Atualizando o GRUB..."
sudo update-grub

echo "[SUCESSO] Parâmetros da Intel aplicados. O notebook estará protegido no próximo boot."
