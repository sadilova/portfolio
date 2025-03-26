from extract_color import rgb_colors
import turtle as t
import random

t.colormode(255)


Tom = t.Turtle()
Tom.hideturtle()
Tom.teleport(-250, -250)

movement = -250
y_value = -250


def draw_row():
    global movement
    for _ in range (10):
        movement += 50
        color = random.choice(rgb_colors)
        Tom.dot(20, color)
        Tom.teleport(movement)
    movement = -250


for _ in range (10):
    draw_row()
    y_value += 50
    Tom.teleport(movement, y_value)

screen = t.Screen()
screen.exitonclick()
