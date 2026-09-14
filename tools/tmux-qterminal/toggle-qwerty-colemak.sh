#!/usr/bin/env bash
#
# Alterna QWERTY BR ABNT2, quatro etapas Tarmak ABNT2 e Colemak ABNT2.
# Na primeira execução, instala a definição XKB e este comando em
# /usr/local/bin. Quando iniciado por um atalho sem terminal, abre o
# QTerminal para que o sudo receba um PTY real.

set -euo pipefail

readonly TARGET="/usr/local/bin/qwerty-colemak"
readonly XKB_BR="/usr/share/X11/xkb/symbols/br"
readonly XKB_RULES_XML="/usr/share/X11/xkb/rules/evdev.xml"
readonly XKB_RULES_LST="/usr/share/X11/xkb/rules/evdev.lst"
readonly USER_IBUS_COMPONENT="${XDG_DATA_HOME:-$HOME/.local/share}/ibus/component/qwerty-colemak.xml"
readonly QWERTY_ENGINE="xkb:br::por"
readonly TARMARK1_ENGINE="xkb:br:tarmak_abnt2_1:por"
readonly TARMARK2_ENGINE="xkb:br:tarmak_abnt2_2:por"
readonly TARMARK3_ENGINE="xkb:br:tarmak_abnt2_3:por"
readonly TARMARK4_ENGINE="xkb:br:tarmak_abnt2_4:por"
readonly COLEMAK_ENGINE="xkb:br:colemak_abnt2:por"
readonly IBUS_ENGINES="['${QWERTY_ENGINE}', '${TARMARK1_ENGINE}', '${TARMARK2_ENGINE}', '${TARMARK3_ENGINE}', '${TARMARK4_ENGINE}', '${COLEMAK_ENGINE}']"
readonly XKB_BEGIN="// BEGIN qwerty-colemak XKB"
readonly XKB_END="// END qwerty-colemak XKB"
readonly LEGACY_MARKER="// qwerty-colemak: Tiago Egas Colemak ABNT2"
script_path() {
    readlink -f "$0"
}
rules_installed() {
    grep -Eq '^[[:space:]]+colemak_abnt2[[:space:]]+br:' "$XKB_RULES_LST" 2>/dev/null
}

ibus_engines_installed() {
    grep -Fq "<name>${COLEMAK_ENGINE}</name>" "$USER_IBUS_COMPONENT" 2>/dev/null
}

layout_installed() {
    grep -Fq "$XKB_BEGIN" "$XKB_BR" 2>/dev/null &&
        rules_installed &&
        ibus_engines_installed
}

write_layout() {
    cat <<'XKB'

// BEGIN qwerty-colemak XKB
// Colemak ABNT2 ported from Tiago-Egas/Colemak_ABNT2 (GPL-3.0-only).
// Tarmak stages follow the original ETROI transition mappings:
// https://github.com/azmr/tarmak-cli/blob/master/keychanges.txt

partial alphanumeric_keys
xkb_symbols "colemak_abnt2" {
    include "br(abnt2)"
    name[Group1] = "Portuguese (Brazil, Colemak ABNT2, Tiago Egas)";

    // Q W F P G J L U Y Ç
    key <AD03> { [ f, F, degree, degree ] };
    key <AD04> { [ p, P, registered, registered ] };
    key <AD05> { [ g, G ] };
    key <AD06> { [ j, J ] };
    key <AD07> { [ l, L ] };
    key <AD08> { [ u, U ] };
    key <AD09> { [ y, Y ] };
    key <AD10> { [ ccedilla, Ccedilla ] };

    // A R S T D H N E I O
    key <AC02> { [ r, R ] };
    key <AC03> { [ s, S ] };
    key <AC04> { [ t, T ] };
    key <AC05> { [ d, D ] };
    key <AC06> { [ h, H ] };
    key <AC07> { [ n, N ] };
    key <AC08> { [ e, E ] };
    key <AC09> { [ i, I ] };
    key <AC10> { [ o, O ] };

    // Z X C V B K M , . ;
    key <AB03> { [ c, C, 0x10020A2, 0x10020A2 ] };
    key <AB06> { [ k, K ] };
    key <AB07> { [ m, M ] };
};

partial alphanumeric_keys
xkb_symbols "tarmak_abnt2_1" {
    include "br(abnt2)"
    name[Group1] = "Portuguese (Brazil, Tarmak ABNT2 1, E)";

    // Canonical Tarmak 1: J > E > K > N loop.
    key <AD03> { [ j, J, degree, degree ] };
    key <AC07> { [ n, N ] };
    key <AC08> { [ e, E ] };
    key <AB06> { [ k, K ] };
};

partial alphanumeric_keys
xkb_symbols "tarmak_abnt2_2" {
    include "br(abnt2)"
    name[Group1] = "Portuguese (Brazil, Tarmak ABNT2 2, ET)";

    // Tarmak 1 plus J > G > T > F loop.
    key <AD03> { [ f, F, degree, degree ] };
    key <AD05> { [ g, G ] };
    key <AC04> { [ t, T ] };
    key <AC05> { [ j, J ] };
    key <AC07> { [ n, N ] };
    key <AC08> { [ e, E ] };
    key <AB06> { [ k, K ] };
};

partial alphanumeric_keys
xkb_symbols "tarmak_abnt2_3" {
    include "br(abnt2)"
    name[Group1] = "Portuguese (Brazil, Tarmak ABNT2 3, ETR)";

    // Tarmak 2 plus J > R > S > D loop.
    key <AD03> { [ f, F, degree, degree ] };
    key <AD04> { [ j, J, registered, registered ] };
    key <AD05> { [ g, G ] };
    key <AC02> { [ r, R ] };
    key <AC03> { [ s, S ] };
    key <AC04> { [ t, T ] };
    key <AC05> { [ d, D ] };
    key <AC07> { [ n, N ] };
    key <AC08> { [ e, E ] };
    key <AB06> { [ k, K ] };
};

partial alphanumeric_keys
xkb_symbols "tarmak_abnt2_4" {
    include "br(abnt2)"
    name[Group1] = "Portuguese (Brazil, Tarmak ABNT2 4, ETRO)";

    // Tarmak 3 plus the Tiago Egas ABNT2 equivalent of the O loop.
    key <AD03> { [ f, F, degree, degree ] };
    key <AD04> { [ p, P, registered, registered ] };
    key <AD05> { [ g, G ] };
    key <AD06> { [ j, J ] };
    key <AD09> { [ y, Y ] };
    key <AD10> { [ ccedilla, Ccedilla ] };
    key <AC02> { [ r, R ] };
    key <AC03> { [ s, S ] };
    key <AC04> { [ t, T ] };
    key <AC05> { [ d, D ] };
    key <AC07> { [ n, N ] };
    key <AC08> { [ e, E ] };
    key <AC10> { [ o, O ] };
    key <AB06> { [ k, K ] };
};
// END qwerty-colemak XKB
XKB
}

open_install_terminal() {
    local self
    self="$(script_path)"

    if ! command -v qterminal >/dev/null 2>&1; then
        notify-send --app-name=QTerminal "Colemak ABNT2" \
            "A instalação precisa de um terminal para pedir a senha do sudo." \
            -i input-keyboard 2>/dev/null || true
        printf 'Erro: execute "%s --install" em um terminal.\n' "$self" >&2
        exit 1
    fi

    local wrapper
    wrapper="$(mktemp -t qwerty_install_XXXXXX.sh)"

    cat >"$wrapper" <<WRAPPER
#!/bin/bash
export QWERTY_INSTALL_PTY=1
"$self" --install > /tmp/colemak_install.log 2>&1
status=\$?
cat /tmp/colemak_install.log
echo
if [ "\$status" -ne 0 ]; then
    echo "Houve um erro na instalação (código \$status)."
fi
read -r -p "Pressione Enter para fechar..." _
rm -f "$wrapper"
exit "\$status"
WRAPPER
    chmod +x "$wrapper"
    exec qterminal --execute "$wrapper"
}

install_xkb_layouts() {
    local temporary
    temporary="$(mktemp)"
    if grep -Fq "$XKB_BEGIN" "$XKB_BR"; then
        awk "
            /^${XKB_BEGIN//\//\\/}$/ { skip=1 }
            /^${XKB_END//\//\\/}$/ { skip=0; next }
            !skip { print }
        " "$XKB_BR" >"$temporary"
    elif grep -Fq "$LEGACY_MARKER" "$XKB_BR"; then
        awk "/^${LEGACY_MARKER//\//\\/}$/ { exit } { print }" "$XKB_BR" >"$temporary"
    else
        cat "$XKB_BR" >"$temporary"
    fi

    write_layout >>"$temporary"
    sudo install -o root -g root -m 644 "$temporary" "$XKB_BR"
    rm -f "$temporary"
}
install_xkb_rules() {
    local temporary_xml temporary_lst
    temporary_xml="$(mktemp)"
    temporary_lst="$(mktemp)"

    python3 - "$XKB_RULES_XML" "$XKB_RULES_LST" "$temporary_xml" "$temporary_lst" >/tmp/python_install.log 2>&1 <<'PY'
import re
import sys
from pathlib import Path

xml_path, lst_path, output_xml, output_lst = map(Path, sys.argv[1:])
names = ("tarmak_abnt2_1", "tarmak_abnt2_2", "tarmak_abnt2_3", "tarmak_abnt2_4", "colemak_abnt2")
descriptions = (
    "Portuguese (Brazil, Tarmak ABNT2 1, E)",
    "Portuguese (Brazil, Tarmak ABNT2 2, ET)",
    "Portuguese (Brazil, Tarmak ABNT2 3, ETR)",
    "Portuguese (Brazil, Tarmak ABNT2 4, ETRO)",
    "Portuguese (Brazil, Colemak ABNT2, Tiago Egas)",
)
variants = "\n".join(
    f"""        <variant>
          <configItem>
            <name>{name}</name>
            <description>{description}</description>
          </configItem>
        </variant>"""
    for name, description in zip(names, descriptions)
)
xml_block = f"""
        <!-- BEGIN qwerty-colemak XKB -->
{variants}
        <!-- END qwerty-colemak XKB -->"""

xml = xml_path.read_text()
xml = re.sub(
    r"\s*<!-- BEGIN qwerty-colemak XKB -->.*?<!-- END qwerty-colemak XKB -->",
    "",
    xml,
    flags=re.DOTALL,
)
# Remove the obsolete top-level layout written by the initial installer.
xml = re.sub(
    r"\s*<layout>\s*<configItem>\s*<name>colemak_abnt2</name>.*?</layout>",
    "",
    xml,
    flags=re.DOTALL,
)
br_variant_list = re.compile(
    r"(<layout>\s*<configItem>\s*<name>br</name>.*?<variantList>)",
    flags=re.DOTALL,
)
xml, count = br_variant_list.subn(r"\g<1>" + xml_block, xml, count=1)
if count != 1:
    raise SystemExit("Não foi possível localizar a lista de variantes BR no XKB.")
Path(output_xml).write_text(xml)

lst = lst_path.read_text()
lst = re.sub(
    r"(?m)^[ \t]*(?:tarmak_abnt2_[1-4]|colemak_abnt2)[ \t]+br:.*\n?",
    "",
    lst,
)
lst_entries = "".join(
    f"  {name:<16} br: {description}\n"
    for name, description in zip(names, descriptions)
)
lst, count = re.subn(r"(?m)^(\s*rus\s+br:.*\n)", r"\g<1>" + lst_entries, lst, count=1)
if count != 1:
    raise SystemExit("Não foi possível localizar as variantes BR no evdev.lst.")
Path(output_lst).write_text(lst)
PY

    sudo install -o root -g root -m 644 "$temporary_xml" "$XKB_RULES_XML"
    sudo install -o root -g root -m 644 "$temporary_lst" "$XKB_RULES_LST"
    rm -f "$temporary_xml" "$temporary_lst"
}


install() {
    if [[ -z "${QWERTY_INSTALL_PTY:-}" ]] && { [[ ! -t 0 ]] || [[ ! -t 1 ]]; }; then
        open_install_terminal
    fi

    printf 'Instalando Colemak ABNT2 e Tarmak ABNT2. O sudo pedirá sua senha.\n'
    sudo -v
    install_xkb_layouts
    install_xkb_rules
    sudo install -m 755 "$(script_path)" "$TARGET"

    local variant
    for variant in tarmak_abnt2_1 tarmak_abnt2_2 tarmak_abnt2_3 tarmak_abnt2_4 colemak_abnt2; do
        setxkbmap -print -layout br -variant "$variant" >/dev/null
    done

    printf 'Instalação concluída. Use Super+Space ou "%s".\n' "$TARGET"
}

check() {
    local variant

    if ! layout_installed; then
        printf 'XKB: não instalado\n'
        return 1
    fi

    printf 'XKB: instalado\n'
    for variant in tarmak_abnt2_1 tarmak_abnt2_2 tarmak_abnt2_3 tarmak_abnt2_4 colemak_abnt2; do
        setxkbmap -print -layout br -variant "$variant" >/dev/null
        printf 'XKB: %s validado\n' "$variant"
    done

    if [[ -x "$TARGET" ]] && cmp -s "$(script_path)" "$TARGET"; then
        printf 'Comando global: atualizado\n'
    else
        printf 'Comando global: desatualizado, o atalho IceWM usa este script\n'
    fi
}

case "${1:-}" in
    --install)
        install || { echo "Falhou com $?"; read -r -p "Pressione Enter..." _; exit 1; }
        read -r -p "Pressione Enter para concluir..." _
        exit 0
        ;;
    --check)
        check
        exit 0
        ;;
    --help|-h)
        printf 'Uso: %s [--install|--check]\n' "$(script_path)"
        exit 0
        ;;
esac

if ! layout_installed || [[ ! -x "$TARGET" ]] || ! cmp -s "$(script_path)" "$TARGET"; then
    install
fi

current_variant="$(setxkbmap -query | sed -n 's/^variant:[[:space:]]*//p')"

case "$current_variant" in
    "")
        setxkbmap -layout br -variant tarmak_abnt2_1
        notify-send --app-name=QTerminal "Treino Nível 1" "Layout atual: Tarmak ABNT2 1, E" -i input-keyboard
        ;;
    tarmak_abnt2_1)
        setxkbmap -layout br -variant tarmak_abnt2_2
        notify-send --app-name=QTerminal "Treino Nível 2" "Layout atual: Tarmak ABNT2 2, ET" -i input-keyboard
        ;;
    tarmak_abnt2_2)
        setxkbmap -layout br -variant tarmak_abnt2_3
        notify-send --app-name=QTerminal "Treino Nível 3" "Layout atual: Tarmak ABNT2 3, ETR" -i input-keyboard
        ;;
    tarmak_abnt2_3)
        setxkbmap -layout br -variant tarmak_abnt2_4
        notify-send --app-name=QTerminal "Treino Nível 4" "Layout atual: Tarmak ABNT2 4, ETRO" -i input-keyboard
        ;;
    tarmak_abnt2_4)
        setxkbmap -layout br -variant colemak_abnt2
        notify-send --app-name=QTerminal "Teclado alterado" "Layout atual: Colemak ABNT2, Tiago Egas" -i input-keyboard
        printf 'Mudou para Colemak ABNT2, Tiago Egas.\n'
        ;;
    *)
        setxkbmap -layout br
        notify-send --app-name=QTerminal "Teclado resetado" "Layout atual: QWERTY, BR ABNT2" -i input-keyboard
        printf 'Mudou para QWERTY, BR ABNT2.\n'
        ;;
esac
