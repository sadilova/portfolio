from turtle import Screen
from snake import Snake
import time
from food import Food
from scoreboard import Scoreboard

screen = Screen()
screen.setup(600, 600)
screen.bgcolor("black")
screen.title("Snake")
screen.tracer(0)

snake = Snake()
food = Food()
scoreboard = Scoreboard()

START = 0

screen.listen()
screen.onkey(snake.up, "Up")
screen.onkey(snake.down, "Down")
screen.onkey(snake.left, "Left")
screen.onkey(snake.right, "Right")

game = True
screen.update()

while game:
    time.sleep(0.1)
    snake.move()
    screen.update()

    # Detect collision with wall
    if snake.head.xcor() > 280 or snake.head.xcor() < -280 or snake.head.ycor() > 280 or snake.head.ycor() < -280:
        game = False
        scoreboard.game_over()

    # Detect collision with food
    if snake.head.distance(food) < 10:
        food.refresh()
        scoreboard.increase_score()
        snake.grow_tail()
        screen.update()

    # Detect collision with tail
    for seg in snake.all_segments[1:]:
        if snake.head.distance(seg) < 10:
            game = False
            scoreboard.game_over()

screen.exitonclick()
