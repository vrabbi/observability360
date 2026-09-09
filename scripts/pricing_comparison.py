import matplotlib.pyplot as plt
from matplotlib.ticker import StrMethodFormatter
import numpy as np
from tabulate import tabulate

RETENTION_PERIOD = 30  # days

# Pricing information based on the search results
pricing_info = {
    "Datadog": {
        "free_gb_per_month": 0,  
        "ingestion_per_gb": 2.6,
        "retention_per_gb_per_day": 0.0 
    },

    "Dynatrace": {
        "free_gb_per_month": 0,  
        "ingestion_per_gb": 0.20,  
        "retention_per_gb_per_day": 0.02 
    },

    "New Relic": {
        "free_gb_per_month": 100,  
        "ingestion_per_gb": 0.55,  
        "retention_per_gb_per_day": 0
    },

    "Azure Data Explorer": {
        "total_cost_per_gb": {
            100: 620,
            125: 621,
            150: 621,
            175: 622,
            200: 623,
            300: 624,
            400: 625,
            500: 626,
            600: 627,
            700: 628,
            800: 886,
            900: 887,
            1000: 888,
            2000: 1704,
            3000: 2369,
            4000: 2528,
            5000: 2541,
            6000: 2554,
            7000: 2567,
            8000: 2580,
            9000: 2593,
            10000: 2606,
            20000: 2736,
            30000: 3964,
            40000: 5192,
            50000: 5322,
            60000: 7647,
            70000: 7777,
            80000: 10103,
            90000: 10233,
            100000: 10363,
            200000: 20455,
            300000: 30528,
            400000: 41412,
            500000: 51494,
            600000: 61576,
            700000: 71659,
            800000: 81741,
            900000: 91824,
            1000000: 101906,
        }
    }
}

# Use Azure Data Explorer's granular data points as the x-axis
scales = sorted(pricing_info["Azure Data Explorer"]["total_cost_per_gb"].keys())
platforms = list(pricing_info.keys())

# Prepare data for plotting
platform_costs = {platform: [] for platform in platforms}

for scale in scales:
    for platform in platforms:
        if platform == "Azure Data Explorer":
            # For Azure Data Explorer, we need to use the total cost per GB
            cost = pricing_info[platform]["total_cost_per_gb"].get(scale, 0)
        else:
            # Calculate the cost for other platforms
            free_gb = pricing_info[platform]["free_gb_per_month"]
            ingestion_cost = max(0, (scale - free_gb)) * pricing_info[platform]["ingestion_per_gb"]
            retention_cost = scale * RETENTION_PERIOD * pricing_info[platform]["retention_per_gb_per_day"]
            cost = ingestion_cost + retention_cost
        platform_costs[platform].append(cost)

# Define ranges for the three graphs
ranges = [
    (100, 1000, 'pricing_comparison_100_to_1000.png'),
    (1000, 10000, 'pricing_comparison_1000_to_10000.png'),
    (10000, 100000, 'pricing_comparison_10000_to_100000.png'),
    (100000, 1000000, 'pricing_comparison_100000_to_1000000.png')
]

# Plot each range separately
for start, end, filename in ranges:
    plt.figure(figsize=(12, 8))
    for platform, costs in platform_costs.items():
        # Filter data for the current range
        filtered_scales = [scale for scale in scales if start <= scale <= end]
        filtered_costs = [cost for scale, cost in zip(scales, costs) if start <= scale <= end]
        plt.plot(filtered_scales, filtered_costs, marker='o', linestyle='-', label=platform)

    plt.xlabel('Monthly Data Ingestion (GB)')
    plt.ylabel('Cost (USD)')
    plt.title(f'Pricing Comparison Across Platforms ({start} to {end} GB)')
    plt.xticks(filtered_scales, rotation=45)
    plt.legend()
    plt.tight_layout(pad=4.0)
    plt.gca().xaxis.set_major_formatter(StrMethodFormatter('{x:,.0f}'))  # Format x-axis with commas
    plt.gca().yaxis.set_major_formatter(StrMethodFormatter('{x:,.0f}'))  # Format y-axis with commas

    plt.savefig(filename)

    print(f"Graph for range {start} to {end} GB has been generated and saved as {filename}.")

# Generate tables for each range as PNG images
for start, end, filename in ranges:
    table_data = []
    headers = ["Scale (GB)"] + platforms

    for scale in scales:
        if start <= scale <= end:
            row = [scale]
            for platform in platforms:
                cost_index = scales.index(scale)
                row.append(platform_costs[platform][cost_index])
            table_data.append(row)

    # Create a figure for the table
    fig, ax = plt.subplots(figsize=(12, len(table_data) * 0.5))  # Adjust height based on the number of rows
    ax.axis('tight')
    ax.axis('off')
    table = ax.table(cellText=table_data, colLabels=headers, cellLoc='center', loc='center')
    table.auto_set_font_size(False)
    table.set_fontsize(10)
    table.auto_set_column_width(col=list(range(len(headers))))

    # Save the table as a PNG image
    table_filename = filename.replace('.png', '_table.png')
    plt.savefig(table_filename, bbox_inches='tight')
    plt.close()
