#!/usr/bin/env python3
"""
Uncompress the Breast Cancer GSE45827 dataset.
After cloning from GitHub, run this script to decompress the dataset.
"""

import os
import gzip
from pathlib import Path

def decompress_dataset():
    base_dir = Path('Estadística para analitica de datos')
    gz_file = base_dir / 'Breast_GSE45827.csv.gz'
    csv_file = base_dir / 'Breast_GSE45827.csv'
    
    if csv_file.exists():
        print(f'✓ {csv_file.name} already exists. Skipping decompression.')
        return
    
    if not gz_file.exists():
        print(f'✗ {gz_file.name} not found.')
        return
    
    print(f'Decompressing {gz_file.name}...')
    with gzip.open(gz_file, 'rb') as f_in:
        with open(csv_file, 'wb') as f_out:
            f_out.write(f_in.read())
    
    size_mb = csv_file.stat().st_size / (1024**2)
    print(f'✓ Decompressed to {csv_file.name} ({size_mb:.2f} MB)')

if __name__ == '__main__':
    decompress_dataset()
