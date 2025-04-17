import numpy as np
import pandas as pd
import plotly.express as px
from scipy.stats import pearsonr


def generate_data():
    dates = pd.date_range(start="2025-03-05", end="2025-03-11", freq="H")
    num_points = len(dates)

    experiments = ["food_1", "food_2", "food_3", "food_4", "food_5"]
    sensors = ["sensor_1", "sensor_2", "sensor_3"]
    water_control = "water_control"

    data_gen = []

    def sigmoid(x, L=600, x0=0.9, k=10):
        return L / (1 + np.exp(-k * (x - x0)))

    x_values = np.linspace(0, 1, num_points)
    water_baseline_samples = []

    for sensor in sensors:
        multiplier = np.random.uniform(20, 100)
        baseline = np.sqrt(x_values * multiplier)
        offset = np.random.uniform(3, 10)
        water_values = baseline + offset
        water_baseline_samples.append(water_values)

        for i, date in enumerate(dates):
            data_gen.append([date, water_control, sensor, water_values[i]])

    mean_water_baseline = np.mean(water_baseline_samples, axis=0)

    for experiment in experiments:
        for sensor in sensors:
            multiplier = np.random.uniform(20, 100)
            chicken_raw = np.sqrt(x_values * multiplier)

            chicken_baseline = chicken_raw.copy()
            chicken_baseline_mean = np.mean(chicken_baseline[:int(0.5 * num_points)])
            target_mean = np.mean(mean_water_baseline[:int(0.5 * num_points)]) + np.random.uniform(-2, 2)
            adjustment = target_mean - chicken_baseline_mean
            chicken_baseline += adjustment

            peak_intensity = np.random.uniform(70, 500)
            peak = sigmoid(x_values, L=peak_intensity, x0=0.9, k=10)
            chicken_values = chicken_baseline + peak

            for i, date in enumerate(dates):
                data_gen.append([date, experiment, sensor, chicken_values[i]])

    df = pd.DataFrame(data_gen, columns=["date", "experiment", "sensor", "admittance"])
    return df


def generate_distance_mapping(df, target_corr_range=(-0.9, -0.5), max_iter=5000, random_state=None):
    if random_state is not None:
        np.random.seed(random_state)

    # Step 1: Compute mean admittance per (sensor, experiment)
    grouped = df.groupby(['sensor', 'experiment'])['admittance'].mean().reset_index()
    grouped = grouped.rename(columns={'admittance': 'mean_admittance'})

    y = grouped['mean_admittance'].values
    y_std = (y - np.mean(y)) / np.std(y)

    for _ in range(max_iter):
        slope = np.random.uniform(-3, -0.2)  # strong negative slope
        noise = np.random.normal(0, 0.2, size=len(y))  # small noise
        x = slope * y_std + noise

        # Normalize to 0-1
        x_scaled = (x - np.min(x)) / (np.max(x) - np.min(x))
        corr, _ = pearsonr(x_scaled, y)

        if target_corr_range[0] <= corr <= target_corr_range[1]:
            grouped['distance'] = x_scaled

            # Merge the distances back into the original dataframe
            df = df.merge(grouped[['sensor', 'experiment', 'distance']], on=['sensor', 'experiment'], how='left')
            return df

    raise ValueError("Could not generate distances with desired correlation.")

