import pandas as pd
import numpy as np
from datetime import datetime

file_path = 'Viaticos_Registraduria_2022_2025.csv'
df = pd.read_csv(file_path, low_memory=False)

def is_digit(val):
    if pd.isna(val): return False
    s = str(val).strip()
    return s.isdigit()

def parse_date(val):
    if pd.isna(val): return None
    try:
        return datetime.strptime(str(val).strip(), '%d/%m/%Y')
    except:
        return None

# Initial candidate counts
df['is_valid'] = True

# commission_request_id con dígitos
df['commission_request_id_clean'] = df['commission_request_id'].apply(lambda x: str(int(float(x))) if pd.notna(x) and str(x).replace('.0','').isdigit() else None)
df.loc[df['commission_request_id_clean'].isna(), 'is_valid'] = False

# employee_id con dígitos
df['employee_id_clean'] = df['employee_id'].apply(lambda x: str(int(float(x))) if pd.notna(x) and str(x).replace('.0','').isdigit() else None)
df.loc[df['employee_id_clean'].isna(), 'is_valid'] = False

# year con dígitos o año de start_date
df['start_dt'] = df['start_date'].apply(parse_date)
df['end_dt'] = df['end_date'].apply(parse_date)

def get_year(row):
    y = str(row['year']).strip() if pd.notna(row['year']) else ""
    if y.isdigit():
        return y
    if row['start_dt']:
        return str(row['start_dt'].year)
    return None

df['year_clean'] = df.apply(get_year, axis=1)
df.loc[df['year_clean'].isna(), 'is_valid'] = False

# route no vacía
df.loc[df['route'].isna() | (df['route'].astype(str).str.strip() == ""), 'is_valid'] = False

# origen_register no vacío
df.loc[df['origen_register'].isna() | (df['origen_register'].astype(str).str.strip() == ""), 'is_valid'] = False

# dates válidas y start_date <= end_date
df.loc[df['start_dt'].isna(), 'is_valid'] = False
df.loc[df['end_dt'].isna(), 'is_valid'] = False
df.loc[df['is_valid'] & (df['start_dt'] > df['end_dt']), 'is_valid'] = False

candidates = df[df['is_valid']].copy()
print(f"candidate_fact_rows: {len(candidates)}")

# Deduplicate
# Identificar duplicados por (commission_request_id_clean, year_clean)
# Quedar con mayor end_date y luego mayor start_date
candidates = candidates.sort_values(by=['commission_request_id_clean', 'year_clean', 'end_dt', 'start_dt'], ascending=[True, True, False, False])

# Para los ejemplos, buscamos grupos con más de una fila
groups = candidates.groupby(['commission_request_id_clean', 'year_clean'])
duplicates = groups.filter(lambda x: len(x) > 1)

print("\nEjemplos de deduplicación:")
count_ex = 0
for name, group in duplicates.groupby(['commission_request_id_clean', 'year_clean']):
    if count_ex >= 3: break
    print(f"Llave: {name}")
    for i, row in group.iterrows():
        status = "GANADORA" if i == group.index[0] else "DESCARTADA"
        print(f"  - {status}: Start: {row['start_date']}, End: {row['end_date']}")
    count_ex += 1

final_df = candidates.drop_duplicates(subset=['commission_request_id_clean', 'year_clean'])
print(f"\nfact_rows_finales: {len(final_df)}")
