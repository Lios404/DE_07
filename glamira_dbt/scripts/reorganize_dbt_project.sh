#!/bin/bash
set -e

cd ~/glamira-pipeline/glamira_dbt

# ============ 1. RENAME FILE YML THEO CONVENTION (dau _ de sort len dau) ============
mv models/staging/sources.yml models/staging/_sources.yml
mv models/core/schema.yml models/core/_core_models.yml
mv models/mart/schema.yml models/mart/_mart_models.yml

# ============ 2. DON CAC MODEL MAU CUA DBT INIT (neu con sot) ============
rm -rf models/example

# ============ 3. TAO THU MUC LUU LAI SCRIPT DEBUG (gia tri portfolio) ============
mkdir -p scripts
mv ~/glamira-pipeline/setup_dbt_models.sh scripts/ 2>/dev/null || true
mv ~/glamira-pipeline/rebuild_dbt_models_v2.sh scripts/ 2>/dev/null || true
mv ~/glamira-pipeline/rebuild_dbt_models_v3.sh scripts/ 2>/dev/null || true
mv ~/glamira-pipeline/fix_dbt_test_failures.sh scripts/ 2>/dev/null || true
mv ~/glamira-pipeline/create_mart_layer.sh scripts/ 2>/dev/null || true
# (neu ban da chay cac script nay ben trong glamira_dbt/ thay vi glamira-pipeline/, doi lai duong dan tim ben tren)
find ~/glamira-pipeline/glamira_dbt -maxdepth 1 -name "*.sh" -exec mv {} scripts/ \;

# ============ 4. TAO THU MUC SNAPSHOTS (rong, chuan bi cho SCD2 that su sau nay) ============
mkdir -p snapshots
touch snapshots/.gitkeep

# ============ 5. .GITIGNORE CHO DBT PROJECT ============
cat > .gitignore << 'EOF'
target/
dbt_packages/
logs/
.user.yml
EOF

# ============ 6. KIEM TRA CO NESTED .git KHONG (dbt init doi khi tu tao) ============
if [ -d ".git" ]; then
    echo "CANH BAO: phat hien .git rieng trong glamira_dbt/ - can xoa de tranh xung dot voi repo chinh"
    rm -rf .git
    echo "Da xoa .git rieng cua glamira_dbt"
fi

echo "=========================================="
echo "Cau truc sau khi don:"
find . -maxdepth 3 -not -path "./target*" -not -path "./dbt_packages*" -not -path "./logs*" | sort
echo "=========================================="
