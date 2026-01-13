import random
import csv
import math

# -----------------------------
# Configuration
# -----------------------------
N = 1024            # Vector length
BITSIZE = 10        # Bits per element
NUM_SAMPLES = 100   # Number of tests

OUTPUT_INPUT_FILE = "golden_inputs.csv"
OUTPUT_REF_FILE   = "golden_references.csv"

# -----------------------------
# Helper functions
# -----------------------------
def rand_value(bits):
    """Generate a random integer within the allowed bit range."""
    return random.randint(0, (1 << bits) - 1)

# -----------------------------
# Generate samples
# -----------------------------
all_inputs = []
all_refs = []

print(f"Generating {NUM_SAMPLES} samples for Dot Product & Euclidean Dist...")

for _ in range(NUM_SAMPLES):
    # Generate random vectors
    a = [rand_value(BITSIZE) for _ in range(N)]
    b = [rand_value(BITSIZE) for _ in range(N)]
    
    # --- Calculate References ---
    
    # 1. Dot Product (Integer)
    dot_prod = sum(x * y for x, y in zip(a, b))

    # 2. Euclidean Distance (Q16.16)
    # Sqrt(Sum((A-B)^2))
    ssd = sum((x - y)**2 for x, y in zip(a, b))
    euc_float = math.sqrt(ssd)
    
    # Convert to Q16.16 (multiply by 2^16 and truncate)
    euc_fixed = int(euc_float * 65536)

    # Save inputs (A followed by B)
    all_inputs.append(a + b)

    # Save results (Dot Prod, Euc Dist)
    all_refs.append([dot_prod, euc_fixed])

# -----------------------------
# Write files
# -----------------------------

# Write inputs to csv
print(f"Writing {OUTPUT_INPUT_FILE}...")
with open(OUTPUT_INPUT_FILE, "w", newline="") as f:
    writer = csv.writer(f)
    # Header: A0..A1023, B0..B1023
    header = [f"A{i}" for i in range(N)] + [f"B{i}" for i in range(N)]
    writer.writerow(header)
    for row in all_inputs:
        writer.writerow(row)

# Write outputs to csv
print(f"Writing {OUTPUT_REF_FILE}...")
with open(OUTPUT_REF_FILE, "w", newline="") as f:
    writer = csv.writer(f)
    # Header
    writer.writerow(["DOT_PROD", "EUC_DIST_Q16"])
    for row in all_refs:
        writer.writerow(row)

print("Files generated successfully.")