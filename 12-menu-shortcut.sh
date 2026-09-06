#!/bin/bash
# ==============================================================================
# RARETRICCKS MULTI PROTOCOL - 12-menu-shortcut.sh
# Global 'menu' command banata hai — install ke baad kahin se bhi terminal mein
# sirf "menu" likh ke Enter dabao, panel ka interactive menu khul jayega.
#
# Usage: bash 12-menu-shortcut.sh
# ==============================================================================
set -e
source /etc/raretriccks/00-common.sh 2>/dev/null || true

SHORTCUT="/usr/local/bin/menu"

cat > "$SHORTCUT" <<'EOF'
#!/bin/bash
bash /etc/raretriccks/menu.sh
EOF

chmod +x "$SHORTCUT"

echo -e "\033[0;32m[SUCCESS] 'menu' command ban gaya.\033[0m"
echo -e "Ab kahin se bhi terminal mein sirf \033[1;33mmenu\033[0m likh ke Enter dabao."
