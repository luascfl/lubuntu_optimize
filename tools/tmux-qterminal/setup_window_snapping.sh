#!/bin/bash

echo "Verificando ambiente de janelas..."
WM_NAME=$(wmctrl -m | grep "Name:" | awk '{print $2}')

# 1. Instala o script "motor" (que faz o movimento) na pasta de binários locais
SCRIPT_TARGET="$HOME/.local/bin/window_snap.sh"
mkdir -p "$HOME/.local/bin"

if [ ! -f "$SCRIPT_TARGET" ]; then
    echo "Criando script motor de fallback em $SCRIPT_TARGET..."
    cat << 'EOF' > "$SCRIPT_TARGET"
#!/bin/bash
ACTION=$1
WIN=$(xdotool getactivewindow)
if [ -z "$WIN" ]; then exit 1; fi
eval $(xdotool getdisplaygeometry --shell)
PANEL_HEIGHT=36
WORK_HEIGHT=$((HEIGHT - PANEL_HEIGHT))
HALF_WIDTH=$((WIDTH / 2))
case $ACTION in
    left)
        wmctrl -i -r "$WIN" -b remove,maximized_vert,maximized_horz
        wmctrl -i -r "$WIN" -e 0,0,0,$HALF_WIDTH,$WORK_HEIGHT ;;
    right)
        wmctrl -i -r "$WIN" -b remove,maximized_vert,maximized_horz
        wmctrl -i -r "$WIN" -e 0,$HALF_WIDTH,0,$HALF_WIDTH,$WORK_HEIGHT ;;
    max) wmctrl -i -r "$WIN" -b add,maximized_vert,maximized_horz ;;
    min) xdotool windowminimize "$WIN" ;;
esac
EOF
    chmod +x "$SCRIPT_TARGET"
fi

if [ "$WM_NAME" = "IceWM" ]; then
    echo "Gerenciador IceWM detectado. Usando modo nativo (mais rápido)..."
    PREF_FILE="$HOME/.icewm/preferences"
    mkdir -p "$HOME/.icewm"
    touch "$PREF_FILE"
    
    RELOAD=0
    # Checa e aplica cada atalho
    for KEY_BIND in 'KeyWinMaximize="Super+Up"' 'KeyWinMinimize="Super+Down"' 'KeyWinTileLeft="Super+Left"' 'KeyWinTileRight="Super+Right"'; do
        KEY_NAME=$(echo "$KEY_BIND" | cut -d= -f1)
        if ! grep -q "^$KEY_BIND" "$PREF_FILE"; then
            echo "-> Configurando $KEY_NAME"
            # Remove qualquer configuração antiga/conflitante dessa tecla
            sed -i "/^${KEY_NAME}/d" "$PREF_FILE"
            sed -i "/^# ${KEY_NAME}/d" "$PREF_FILE"
            
            echo "$KEY_BIND" >> "$PREF_FILE"
            RELOAD=1
        else
            echo "-> $KEY_NAME já estava configurado corretamente."
        fi
    done

    if [ "$RELOAD" -eq 1 ]; then
        echo "Recarregando o IceWM para aplicar..."
        icewm -r
    else
        echo "O IceWM já está com todos os atalhos funcionando!"
    fi

else
    echo "Gerenciador $WM_NAME detectado. Para LXQt/Openbox a configuração via script é necessária."
    echo "Certifique-se de que o LXQt está mapeando Meta+Setas para o script ~/.local/bin/window_snap.sh"
fi

echo "Verificação concluída!"
