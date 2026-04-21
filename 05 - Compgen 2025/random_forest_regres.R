
library(randomForest)
library(caret)
library(ggplot2)

data <- read.table("CpGMeth2Age.txt", header = TRUE, sep = "\t")

# Check for missing values
if (any(is.na(data))) {
  cat("Missing values detected. Imputing with median...\n")
  for (col in colnames(data)) {
    data[is.na(data[,col]), col] <- median(data[,col], na.rm = TRUE)
  }
}

# Separate features (X) and target variable (y)
X <- data[, -1]  # All columns except Age
y <- data[, 1]   # Age column

# Split data into training (80%) and testing (20%) sets
set.seed(42)
trainIndex <- createDataPartition(y, p = 0.8, list = FALSE)
X_train <- X[trainIndex, ]
y_train <- y[trainIndex]
X_test <- X[-trainIndex, ]
y_test <- y[-trainIndex]

# Train the random forest model
rf_model <- randomForest(x = X_train, y = y_train, ntree = 500)

# Make predictions on the test set
y_pred <- predict(rf_model, X_test)

r_squared <- 1 - sum((y_test - y_pred)^2) / sum((y_test - mean(y_test))^2)
cat("R-squared:", r_squared, "\n")

# Plot predicted vs actual ages
plot_data <- data.frame(Actual = y_test, Predicted = y_pred)
ggplot(plot_data, aes(x = Actual, y = Predicted)) +
  geom_point() +
  geom_abline(intercept = 0, slope = 1, color = "red", linetype = "dashed") +
  labs(title = "Predicted vs Actual Age",
       x = "Actual Age",
       y = "Predicted Age") +
  theme_minimal()

importance <- importance(rf_model)
top_features <- head(importance[order(importance, decreasing = TRUE), , drop = FALSE], 10)
print("Top 10 most important features:")
print(top_features)
