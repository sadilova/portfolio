from turtle import Turtle


class Scoreboard(Turtle):
    def __init__(self):
        super().__init__()
        self.color("white")
        self.penup()
        self.hideturtle()
        self.score1 = 0
        self.score2 = 0
        self.scoreboard_update()

    def score1_point(self):
        self.score1 += 1
        self.scoreboard_update()

    def score2_point(self):
        self.score2 += 1
        self.scoreboard_update()

    def scoreboard_update(self):
        self.clear()
        self.goto(-100, 200)
        self.write(self.score2, align="center", font=("Courier", 80, "normal"))
        self.goto(100, 200)
        self.write(self.score1, align="center", font=("Courier", 80, "normal"))
