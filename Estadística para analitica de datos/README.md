# Breast Cancer GSE45827 EDA

## Dataset Description
This folder contains exploratory data analysis (EDA) for the Breast Cancer GSE45827 dataset.

- **Samples:** 151 breast cancer samples
- **Features:** 54,675 gene probes (microarray expression data)
- **Class labels:** 6 types (basal, HER, luminal_A, luminal_B, cell_line, normal)

## Files

### Dataset
- `Breast_GSE45827.csv.gz` - Compressed dataset (61 MB). **Decompress before use.**

### EDA Outputs
Located in `eda_outputs/`:
- `summary.txt` - Basic statistics
- `label_distribution.png` - Class distribution histogram
- `top_variable_probes.csv` / `top_variable_probes.png` - Most variable features
- `pca_samples.png` - 2D PCA projection of samples
- `pca_explained_variance.txt` - PCA explained variance
- `sample_correlation.png` - Sample-sample correlation heatmap
- `expression_preview.csv` - First 5 rows × 20 columns preview

### Scripts
- `../breast_cancer_eda.py` - Main EDA script (auto-decompresses CSV if needed)
- `../decompress_dataset.py` - Standalone decompression utility
- `../requirements.txt` - Python dependencies

## Quick Start

### 1. Decompress the dataset
```bash
python3 decompress_dataset.py
```

### 2. Install dependencies
```bash
pip install -r requirements.txt
```

### 3. Run EDA
```bash
python3 breast_cancer_eda.py
```

Outputs will be saved to `eda_outputs/`.

## Dataset Summary
- **Label distribution:** basal (41), HER (30), luminal_B (30), luminal_A (29), cell_line (14), normal (7)
- **Missing values:** None detected
- **Data type:** Gene expression microarray (Affymetrix)

## Notes
- The dataset is stored compressed (`.csv.gz`) to save disk space and facilitate GitHub uploads.
- The first column (`samples`) contains sample IDs.
- The second column (`type`) contains phenotype labels.
- Remaining columns are gene probe names and expression values.
