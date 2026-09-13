import re
import sys
from pathlib import Path

xml_path = Path("/usr/share/X11/xkb/rules/evdev.xml")
lst_path = Path("/usr/share/X11/xkb/rules/evdev.lst")
output_xml = Path("/tmp/out.xml")
output_lst = Path("/tmp/out.lst")

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
    print("Não foi possível localizar a lista de variantes BR no XKB.")
    sys.exit(1)
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
    print("Não foi possível localizar as variantes BR no evdev.lst.")
    sys.exit(1)
Path(output_lst).write_text(lst)
