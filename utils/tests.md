# Test Results

## 2026-01-31

### Build
- `make -C src/TeraLCP`
  - **Result:** success.

### Tests
- `python utils/run_compare_run_lcp_checks.py`
  - **Result:** failed; outputs differ.

#### data/fasta/minishred1_20_002.fa
- **Status:** outputs differ.
- **TeraTools RunLCP:** BWT length = 810,304; runs = 29,872; avg LCP = 3598.071.
- **Naive lcp.py:** BWT length = 807,383; runs = 29,720; avg LCP = 3610.976.
- **Notes:** Run/LCP totals diverge between implementations; investigate differences in run segmentation or input preprocessing.

#### data/fasta/yeast.fasta
- **Status:** outputs differ.
- **TeraTools RunLCP:** BWT length = 24,766,570; runs = 17,481,250; avg LCP = 10.983.
- **Naive lcp.py:** BWT length = 24,312,613; runs = 16,597,412; avg LCP = 51.904.
- **Notes:** Significant LCP average divergence suggests a mismatch in how boundaries or terminators are handled.
