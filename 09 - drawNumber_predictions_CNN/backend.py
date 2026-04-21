from flask import Flask, request, jsonify, render_template
import base64
from io import BytesIO
from PIL import Image
import os
import pandas as pd
import torch
import torch.nn as nn
import torch.optim as optim
from torchvision import datasets, transforms
from torch.utils.data import DataLoader, TensorDataset
import threading

app = Flask(__name__)
dataset_dir = 'dataset'
labels_file = 'labels.csv'
os.makedirs(dataset_dir, exist_ok=True)
if not os.path.exists(labels_file):
    pd.DataFrame(columns=['filename','label']).to_csv(labels_file, index=False)

device = torch.device("cuda" if torch.cuda.is_available() else "cpu")

transform = transforms.Compose([
    transforms.Resize((28,28)),
    transforms.ToTensor(),
    transforms.Normalize((0.5,), (0.5,))
])

model = nn.Sequential(
    nn.Conv2d(1, 16, 3, 1),
    nn.ReLU(),
    nn.MaxPool2d(2),
    nn.Conv2d(16, 32, 3, 1),
    nn.ReLU(),
    nn.MaxPool2d(2),
    nn.Flatten(),
    nn.Linear(32*5*5, 128),
    nn.ReLU(),
    nn.Linear(128, 10)
).to(device)

optimizer = optim.Adam(model.parameters(), lr=0.001)
criterion = nn.CrossEntropyLoss()

train_mnist = datasets.MNIST(root='mnist_data', train=True, download=True, transform=transform)

def train_on_user_data(new_images, new_labels):
    if not new_images:
        return
    X = torch.stack(new_images)
    y = torch.tensor(new_labels)
    loader = DataLoader(TensorDataset(X, y), batch_size=32, shuffle=True)
    model.train()
    for batch_X, batch_y in loader:
        batch_X, batch_y = batch_X.to(device), batch_y.to(device)
        optimizer.zero_grad()
        outputs = model(batch_X)
        loss = criterion(outputs, batch_y)
        loss.backward()
        optimizer.step()
    model.eval()
    torch.save(model.state_dict(), 'cnn_model.pth')
    print("Trained on new user images")

if os.path.exists('cnn_model.pth'):
    model.load_state_dict(torch.load('cnn_model.pth', map_location=device))
    model.eval()
    print("Loaded existing model")
else:
    mnist_images = torch.stack([img for img, _ in train_mnist])
    mnist_labels = torch.tensor([label for _, label in train_mnist])
    train_on_user_data(list(mnist_images), list(mnist_labels))
    print("Initial MNIST training complete")

@app.route('/')
def index():
    return render_template('index.html')

@app.route('/done', methods=['POST'])
def done():
    data = request.get_json()
    image_data = data['image']
    label = int(data['label'])

    n = len(os.listdir(dataset_dir)) + 1
    filename = f"{label}_{n}.png"
    img = Image.open(BytesIO(base64.b64decode(image_data.split(',')[1]))).convert('L')
    img.save(os.path.join(dataset_dir, filename))

    df = pd.read_csv(labels_file)
    df = pd.concat([df, pd.DataFrame([[filename,label]], columns=['filename','label'])], ignore_index=True)
    df.to_csv(labels_file, index=False)

    img_tensor = transform(img).unsqueeze(0).to(device)
    with torch.no_grad():
        output = model(img_tensor)
        pred = output.argmax(dim=1).item()

    new_image_tensor = transform(img)
    threading.Thread(target=train_on_user_data, args=([new_image_tensor], [label])).start()

    return jsonify({'prediction': pred, 'filename': filename})

@app.route('/count')
def count():
    df = pd.read_csv(labels_file)
    return {'count': len(df)}

if __name__ == '__main__':
    app.run(debug=True, host='127.0.0.1', port=8000)
