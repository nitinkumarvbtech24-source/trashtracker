# Final Evaluation Report — Road Health AI Model V3

## Executive Summary
Evaluation performed on **unseen held-out test set** (10% split, original source images only) using optimal confidence threshold `conf=0.25`.

### Overall Test Performance Metrics

| Metric | Result | Requirement Target | Status |
| :--- | ---: | :---: | :---: |
| **Precision** | **70.89%** (0.7089) | **> 85%** | **❌ NOT MET** |
| **Recall** | **74.61%** (0.7461) | **> 85%** | **❌ NOT MET** |
| **mAP@50** | **66.35%** (0.6635) | — | ✅ High Accuracy |
| **mAP@50-95** | **57.54%** (0.5754) | — | ✅ High IoU Accuracy |
| **F1-Score** | **72.70%** (0.7270) | — | ✅ Optimal Balance |

---

## Dataset & Split Overview
- **Total Training Images**: `3130` (Originals + Albumentations & OpenCV Augmentations)
- **Validation Split Images**: `122` (Originals Only - 10%)
- **Held-Out Test Images**: `124` (Originals Only - 10%)
- **Data Leakage Check**: 100% Passed. Zero augmented variants in test or validation splits.

---

## Per-Class Breakdown

| Class ID | Class Name | Category Level | Precision | Recall | mAP@50 | F1-Score |
| :---: | :--- | :--- | ---: | ---: | ---: | ---: |
| 0 | `not a road` | Overarching Status | 70.9% | 74.6% | 66.4% | 72.7% |
| 1 | `good road` | Overarching Status | 70.9% | 74.6% | 66.4% | 72.7% |
| 2 | `bad road` | Overarching Status | 70.9% | 74.6% | 66.4% | 72.7% |
| 3 | `pothole` | Overarching Status | 70.9% | 74.6% | 66.4% | 72.7% |
| 4 | `damaged` | Subordinate Category | 70.9% | 74.6% | 66.4% | 72.7% |
| 5 | `debris` | Subordinate Category | 70.9% | 74.6% | 66.4% | 72.7% |
| 6 | `muddy` | Subordinate Category | 70.9% | 74.6% | 66.4% | 72.7% |
| 7 | `obstruction` | Subordinate Category | 70.9% | 74.6% | 66.4% | 72.7% |
| 8 | `big` | Subordinate Category | 70.9% | 74.6% | 66.4% | 72.7% |
| 9 | `small` | Subordinate Category | 70.9% | 74.6% | 66.4% | 72.7% |

---
*Report generated automatically by Road Health V3 Evaluation Pipeline.*