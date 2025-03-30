library(data.table)
library(cluster)
library(factoextra)
library(ggplot2)

leukemia_data <- fread("leukemiaExp.txt", data.table = FALSE)
rownames(leukemia_data) <- leukemia_data[[1]]
leukemia_data <- leukemia_data[, -1]

# Select top 1000 most variable genes
gene_var <- apply(leukemia_data, 1, var)
top_1000_genes <- names(sort(gene_var, decreasing = TRUE))[1:1000]
leukemia_subset <- leukemia_data[top_1000_genes, ]

# Transpose the data for clustering (patients as rows)
leukemia_subset_t <- t(leukemia_subset)

# Perform PCA
pca_result <- prcomp(leukemia_subset_t, scale. = TRUE)
pc_scores <- as.data.frame(pca_result$x)

# Add cluster assignments to the PC scores dataframe
pc_scores$Cluster <- as.factor(final_clustering$cluster)

# PCA plot
pca_plot <- ggplot(pc_scores, aes(x = PC1, y = PC2, color = Cluster)) +
  geom_point(size = 3, alpha = 0.7) +
  theme_minimal() +
  labs(title = "PCA Plot of Leukemia Samples",
       x = paste0("PC1 (", round(summary(pca_result)$importance[2, 1] * 100, 1), "% variance)"),
       y = paste0("PC2 (", round(summary(pca_result)$importance[2, 2] * 100, 1), "% variance)")) +
  theme(legend.position = "right")

print(pca_plot)
ggsave("leukemia_pca_plot.png", pca_plot, width = 10, height = 8, dpi = 300)
