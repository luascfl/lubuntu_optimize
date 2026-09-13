import re
import sys
from pathlib import Path

lst_path = Path("/usr/share/X11/xkb/rules/evdev.lst")

names = ("tarmak_abnt2_1", "tarmak_abnt2_2", "tarmak_abnt2_3", "tarmak_abnt2_4", "colemak_abnt2")
descriptions = (
    "Portuguese (Brazil, Tarmak ABNT2 1, E)",
    "Portuguese (Brazil, Tarmak ABNT2 2, ET)",
    "Portuguese (Brazil, Tarmak ABNT2 3, ETR)",
    "Portuguese (Brazil, Tarmak ABNT2 4, ETRO)",
    "Portuguese (Brazil, Colemak ABNT2, Tiago Egas)",
)

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
print(lst_entries)
