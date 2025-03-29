library(ggplot2)
library(nortest)
library(car)  

histonemodevsgeneexp <- read.delim("HistoneModeVsGeneExp.txt", header=TRUE, sep="\t")
head(histonemodevsgeneexp) 
str(histonemodevsgeneexp)  
summary(histonemodevsgeneexp)

sum(is.na(histonemodevsgeneexp$H3k4me3))      
sum(is.na(histonemodevsgeneexp$measured_log2)) 

histonemodevsgeneexp <- na.omit(histonemodevsgeneexp)

boxplot(histonemodevsgeneexp$H3k4me3, main="Boxplot of H3K4me3")
boxplot(histonemodevsgeneexp$measured_log2, main="Boxplot of Gene Expression (log2)")

cor.test(histonemodevsgeneexp$H3k4me3, histonemodevsgeneexp$measured_log2)

mod <- lm(measured_log2 ~ H3k4me3, data=histonemodevsgeneexp)
slope <- coef(mod)['H3k4me3']

print(slope)
summary(mod)  # Get coefficients, p-values, R-squared
confint(mod)

ggplot(histonemodevsgeneexp, aes(x=H3k4me3, y=measured_log2)) +
  geom_point() +
  geom_smooth(method="lm", col="blue") +
  labs(title="Linear Regression: Gene Expression vs. H3K4me3",
       x="H3K4me3 Level",
       y="Gene Expression (log2)")

plot(histonemodevsgeneexp$H3k4me3, histonemodevsgeneexp$measured_log2,
     main="Scatterplot of Gene Expression vs H3K4me3",
     xlab="H3K4me3 Level",
     ylab="Gene Expression (log2)", pch=20)
abline(mod, col="blue")

plot(mod$fitted.values, residuals(mod),
     main="Residuals vs Fitted Values",
     xlab="Fitted Values", ylab="Residuals", pch=20)
abline(h=0, col="red")

residuals_mod <- residuals(mod)
ad_test_result <- ad.test(residuals_mod)
print(ad_test_result) 

hist(residuals_mod, main="Histogram of Residuals", col="lightblue")
qqnorm(residuals_mod)
qqline(residuals_mod, col="red")

vif(mod) 
