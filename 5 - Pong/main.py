from turtle import Turtle, Screen
from paddle import Paddle
from ball import Ball
from scoreboard import Scoreboard

PADDLE1 = (350, 0)
PADDLE2 = (-350, 0)


screen = Screen()
screen.setup(width=800, height=600)
screen.bgcolor("black")
screen.tracer(0)

paddle1 = Paddle(PADDLE1)
paddle2 = Paddle(PADDLE2)
ball = Ball()
scoreboard = Scoreboard()

screen.listen()
screen.onkey(fun=paddle1.up, key="Up")
screen.onkey(fun=paddle1.down, key="Down")
screen.onkey(fun=paddle2.up, key="w")
screen.onkey(fun=paddle2.down, key="s")

game = True
while game:
    screen.update()
    ball.move()

    if ball.ycor() > 290 or ball.ycor() < -290:
        ball.bounce()

    if (ball.distance(paddle1) < 50 and 320 < ball.xcor() < 360
            or ball.distance(paddle2) < 50 and -360 < ball.xcor() < -320):
        ball.x_bounce()
        ball.x_move *= 1.1
        ball.y_move *= 1.1

    if ball.xcor() > 380:
        ball.reset_position()
        scoreboard.scoreboard_update()
        scoreboard.score2_point()
    elif ball.xcor() < -380:
        scoreboard.scoreboard_update()
        scoreboard.score1_point()
        ball.reset_position()


screen.exitonclick()
