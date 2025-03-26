from turtle import Turtle
import random


class Food(Turtle):
    def __init__(self):
        super().__init__()
        self.shape("circle")
        self.penup()
        self.shapesize(stretch_len=0.5, stretch_wid=0.5)
        self.color("yellow")
        self.speed("fastest")
        random_x = random.randrange(-260, 260, 20)
        random_y = random.randrange(-260, 260, 20)
        self.goto(random_x, random_y)

    def refresh(self):
        random_x = random.randrange(-260, 260, 20)
        random_y = random.randrange(-260, 260, 20)
        self.goto(random_x, random_y)
