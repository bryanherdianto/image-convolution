import csv
import matplotlib.pyplot as plt
import numpy as np

# Load data from performance_comparison.csv
csv_file = "sim/performance_comparison.csv"
indices = []
names = []
sizes = []
alu_times = []
mmu_times = []
hw_cycles = []
hw_times_us = []

with open(csv_file, "r", encoding="utf-8") as f:
    reader = csv.DictReader(f)
    for row in reader:
        indices.append(int(row["Index"]))
        names.append(row["Kernel Name"])
        sizes.append(row["Size"])
        alu_times.append(float(row["ALU Sim Time (s)"]))
        mmu_times.append(float(row["MMU Sim Time (s)"]))
        hw_cycles.append(int(row["HW Execution Cycles"]))
        hw_times_us.append(float(row["HW Time at 100MHz (us)"]))

# Set stylish typography and color palette
plt.style.use("seaborn-v0_8-whitegrid" if "seaborn-v0_8-whitegrid" in plt.style.available else "default")
fig = plt.figure(figsize=(16, 11), dpi=200)

# Create 2x2 Grid of Subplots
gs = fig.add_gridspec(2, 2, height_ratios=[1.3, 1.0], hspace=0.35, wspace=0.25)

# -----------------------------------------------------------------------------
# Subplot 1 (Top Spanning): Side-by-Side Grouped Bar Chart Across All 25 Kernels
# -----------------------------------------------------------------------------
ax1 = fig.add_subplot(gs[0, :])
x = np.arange(len(names))
width = 0.38

color_alu = "#1f77b4" # Tech Blue
color_mmu = "#ff7f0e" # Vivid Orange

rects1 = ax1.bar(x - width/2, alu_times, width, label="ALU (Spatial Adder Tree)", color=color_alu, alpha=0.9, edgecolor="none")
rects2 = ax1.bar(x + width/2, mmu_times, width, label="MMU (Systolic Matrix Array)", color=color_mmu, alpha=0.9, edgecolor="none")

# Background shade bands for kernel sizes
ax1.axvspan(-0.5, 0.5, color="#f0f3f6", alpha=0.7, zorder=0)
ax1.text(0, 15.2, "1x1", ha="center", fontsize=10, fontweight="bold", color="#555")

ax1.axvspan(0.5, 8.5, color="#ffffff", alpha=0.7, zorder=0)
ax1.text(4.5, 15.2, "3x3 Kernels", ha="center", fontsize=10, fontweight="bold", color="#555")

ax1.axvspan(8.5, 16.5, color="#f0f3f6", alpha=0.7, zorder=0)
ax1.text(12.5, 15.2, "5x5 Kernels", ha="center", fontsize=10, fontweight="bold", color="#555")

ax1.axvspan(16.5, 24.5, color="#ffffff", alpha=0.7, zorder=0)
ax1.text(20.5, 15.2, "7x7 Kernels", ha="center", fontsize=10, fontweight="bold", color="#555")

ax1.set_ylabel("ModelSim Simulation Time (seconds)", fontsize=11, fontweight="bold")
ax1.set_title("ModelSim Execution Time per Kernel: ALU vs. MMU ($100 \\times 100$ Image)", fontsize=13, fontweight="bold", pad=14)
ax1.set_xticks(x)
ax1.set_xticklabels(names, rotation=45, ha="right", fontsize=9)
ax1.set_ylim(0, 16.5)
ax1.legend(loc="upper left", frameon=True, framealpha=0.95, facecolor="white")
ax1.grid(axis="y", linestyle="--", alpha=0.6)

# -----------------------------------------------------------------------------
# Subplot 2 (Bottom Left): Average Simulation Time Grouped by Kernel Size
# -----------------------------------------------------------------------------
ax2 = fig.add_subplot(gs[1, 0])

size_labels = ["1x1", "3x3", "5x5", "7x7"]
alu_avg_by_size = []
mmu_avg_by_size = []

for sz in size_labels:
    sz_alu = [alu_times[i] for i in range(len(sizes)) if sizes[i] == sz]
    sz_mmu = [mmu_times[i] for i in range(len(sizes)) if sizes[i] == sz]
    alu_avg_by_size.append(np.mean(sz_alu))
    mmu_avg_by_size.append(np.mean(sz_mmu))

x_sz = np.arange(len(size_labels))
b1 = ax2.bar(x_sz - width/2, alu_avg_by_size, width, label="ALU Average", color=color_alu, alpha=0.9)
b2 = ax2.bar(x_sz + width/2, mmu_avg_by_size, width, label="MMU Average", color=color_mmu, alpha=0.9)

# Value labels on top of bars
for bar in b1:
    h = bar.get_height()
    ax2.text(bar.get_x() + bar.get_width()/2., h + 0.15, f"{h:.2f}s", ha="center", va="bottom", fontsize=9, fontweight="bold")
for bar in b2:
    h = bar.get_height()
    ax2.text(bar.get_x() + bar.get_width()/2., h + 0.15, f"{h:.2f}s", ha="center", va="bottom", fontsize=9, fontweight="bold")

ax2.set_ylabel("Average Time (seconds)", fontsize=10, fontweight="bold")
ax2.set_title("Average Simulation Time by Kernel Size", fontsize=11, fontweight="bold")
ax2.set_xticks(x_sz)
ax2.set_xticklabels(size_labels, fontsize=10, fontweight="bold")
ax2.set_ylim(0, 10.5)
ax2.legend(loc="upper left", framealpha=0.95)
ax2.grid(axis="y", linestyle="--", alpha=0.6)

# -----------------------------------------------------------------------------
# Subplot 3 (Bottom Right): Line Plot Comparing Execution Trends & Hardware Metric
# -----------------------------------------------------------------------------
ax3 = fig.add_subplot(gs[1, 1])

ax3.plot(x, alu_times, marker="o", markersize=5, linewidth=1.8, label="ALU (seconds)", color=color_alu)
ax3.plot(x, mmu_times, marker="s", markersize=5, linewidth=1.8, label="MMU (seconds)", color=color_mmu)

ax3.set_ylabel("Simulator Wall-Clock Time (s)", fontsize=10, fontweight="bold")
ax3.set_xlabel("Test Index (1 to 25)", fontsize=10, fontweight="bold")
ax3.set_title("Execution Consistency Across Test Matrix", fontsize=11, fontweight="bold")
ax3.set_xticks(np.arange(0, 25, 4))
ax3.set_xticklabels([f"#{i+1}" for i in range(0, 25, 4)], fontsize=9)
ax3.legend(loc="upper left", framealpha=0.95)
ax3.grid(True, linestyle="--", alpha=0.6)

# Add informative callout box on hardware execution speed
textstr = "\n".join([
    "Hardware Silicon Metrics (@ 100 MHz):",
    "• Sustained Throughput: 1 pixel / cycle",
    "• Total Cycles: 10,311 cycles (identical)",
    "• Real FPGA Frame Time: 103.11 µs",
    "• Real FPGA Throughput: ~9,700 FPS"
])
props = dict(boxstyle="round,pad=0.5", facecolor="#e8f4f8", edgecolor="#b8d8e8", alpha=0.9)
ax3.text(0.97, 0.05, textstr, transform=ax3.transAxes, fontsize=8.5,
         verticalalignment="bottom", horizontalalignment="right", bbox=props)

# Overall Title
fig.suptitle("Image Convolution Hardware Accelerator: ALU vs. MMU Benchmark\nSynthesizable VHDL (1x1, 3x3, 5x5, 7x7 Multi-Scale Architecture)",
             fontsize=14, fontweight="bold", y=0.99)

out_chart = "sim/performance_chart.png"
plt.savefig(out_chart, dpi=200, bbox_inches="tight")
plt.close()
print(f"[+] Performance chart saved to: {out_chart}")
