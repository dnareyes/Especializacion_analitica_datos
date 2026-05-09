import os
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from sklearn.decomposition import PCA
from sklearn.preprocessing import StandardScaler
import gzip

# Paths
CSV_PATH = 'Estadística para analitica de datos/Breast_GSE45827.csv'
CSV_GZ_PATH = 'Estadística para analitica de datos/Breast_GSE45827.csv.gz'
OUT_DIR = 'Estadística para analitica de datos/eda_outputs'
os.makedirs(OUT_DIR, exist_ok=True)

# Decompress if needed
if not os.path.exists(CSV_PATH) and os.path.exists(CSV_GZ_PATH):
    print('Decompressing Breast_GSE45827.csv.gz...')
    with gzip.open(CSV_GZ_PATH, 'rb') as f_in:
        with open(CSV_PATH, 'wb') as f_out:
            f_out.write(f_in.read())
    print('Decompression complete.')

def save_text(text, fname):
    with open(os.path.join(OUT_DIR, fname), 'w', encoding='utf-8') as f:
        f.write(text)

# 1) Read a small sample to inspect structure
print('Reading small sample (nrows=5) to inspect columns...')
meta = pd.read_csv(CSV_PATH, nrows=5)
print('Columns sample count:', len(meta.columns))
print('First columns:', meta.columns[:10].tolist())

# 2) Load full dataset (rows = samples, columns = probes)
print('Loading full dataset (this may take a moment)...')
try:
    df = pd.read_csv(CSV_PATH, index_col=0, low_memory=False)
except Exception:
    df = pd.read_csv(CSV_PATH, low_memory=False)
    if 'samples' in df.columns:
        df = df.set_index('samples')

print('Dataframe shape (samples, features):', df.shape)

# Detect phenotype/label column
label_col = None
for candidate in ['type', 'Type', 'class', 'Class', 'phenotype', 'Phenotype', 'label', 'Label']:
    if candidate in df.columns:
        label_col = candidate
        break

if label_col:
    print('Found label column:', label_col)
    labels = df[label_col].astype(str)
    expr = df.drop(columns=[label_col])
else:
    expr = df.copy()
    labels = pd.Series(['Unknown']*expr.shape[0], index=expr.index)

expr = expr.apply(pd.to_numeric, errors='coerce')

# Basic summaries
summary_lines = []
summary_lines.append(f'Samples: {expr.shape[0]}')
summary_lines.append(f'Features (probes): {expr.shape[1]}')
summary_lines.append('\nLabel counts:')
summary_lines.append(str(labels.value_counts()))
summary_lines.append('\nMissing values per sample (first 10):')
summary_lines.append(str(expr.isna().sum(axis=1).head(10)))
summary_lines.append('\nMissing values per feature (first 10):')
summary_lines.append(str(expr.isna().sum(axis=0).head(10)))

save_text('\n'.join(summary_lines), 'summary.txt')
print('Saved summary to', os.path.join(OUT_DIR, 'summary.txt'))

# Plot label distribution
plt.figure(figsize=(6,4))
sns.countplot(x=labels)
plt.title('Label distribution')
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, 'label_distribution.png'))
plt.close()

# Feature variance
vars = expr.var(axis=0, skipna=True).sort_values(ascending=False)
vars.head(20).to_csv(os.path.join(OUT_DIR, 'top_variable_probes.csv'))

plt.figure(figsize=(10,6))
sns.barplot(data=vars.head(20).reset_index(), x=0, y='index', hue='index', palette='viridis', legend=False)
plt.xlabel('Variance')
plt.ylabel('Probe')
plt.title('Top 20 most variable probes')
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, 'top_variable_probes.png'))
plt.close()

# PCA on samples
n_top = 1000
if expr.shape[1] > n_top:
    top_probes = vars.head(n_top).index
    X = expr[top_probes].fillna(expr.mean()).values
else:
    X = expr.fillna(expr.mean()).values

scaler = StandardScaler()
Xs = scaler.fit_transform(X)

pca = PCA(n_components=2)
pcs = pca.fit_transform(Xs)

pca_df = pd.DataFrame(pcs, index=expr.index, columns=['PC1','PC2'])
pca_df['label'] = labels.values

plt.figure(figsize=(7,6))
sns.scatterplot(data=pca_df, x='PC1', y='PC2', hue='label', s=80)
plt.title('PCA (2 components) on samples')
plt.tight_layout()
plt.savefig(os.path.join(OUT_DIR, 'pca_samples.png'))
plt.close()

# Save explained variance
explained = pca.explained_variance_ratio_
with open(os.path.join(OUT_DIR, 'pca_explained_variance.txt'), 'w') as f:
    f.write(str(explained))

# Correlation heatmap between samples
if expr.shape[0] <= 200:
    corr = expr.T.corr()
    plt.figure(figsize=(10,8))
    sns.heatmap(corr, cmap='vlag', center=0)
    plt.title('Sample-sample correlation')
    plt.tight_layout()
    plt.savefig(os.path.join(OUT_DIR, 'sample_correlation.png'))
    plt.close()
else:
    print('Skipping full sample-sample correlation heatmap (too many samples)')

# Save preview
expr.iloc[:5, :20].to_csv(os.path.join(OUT_DIR, 'expression_preview.csv'))

print('EDA complete. Outputs in', OUT_DIR)
