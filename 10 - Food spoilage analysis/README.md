**This analysis was designed to assess the impact of sensor distance from food on the measurement of spoilage.**

## Overview
This analysis investigates the effect of sensor placement on spoilage detection over time. We simulate sensor data and apply distance corrections to analyze the relationship between sensor proximity to food and spoilage detection timing.

## Objectives
- Analyze the relationship between sensor distance and spoilage detection.
- Visualize and interpret trends in corrected admittance values over time.

## Files Included:
- `pack_var_analysis.ipynb`: Jupyter notebook performing the analysis and visualizations.
- `data/`: Folder containing the dataset.

## Key Results
- Sensors closer to the food generally detect spoilage earlier.
- Adjusting for sensor distance generally decreases the measurement of time to spoilage and less variability between sensors within one experiment - providing a better accuracy and faster detection.

## Requirements
- Python 3.x
- Required libraries:
  - pandas
  - plotly
  - numpy
  - scipy
  - sklearn
  - matplotlib
  - plotly_express

## How to Run the Notebook
1. Clone this repository.
2. Install the required dependencies using `pip install -r requirements.txt`.
3. Run the Jupyter notebook `pack_var_analysis.ipynb` to view the analysis and visualizations.


Given that the dataset is randomly generated (albeit with a built-in negative correlation to spoilage), the effect of distance correction may not always produce a noticeable influence.

