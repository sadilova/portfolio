import turtle

START = [(0, 0), (-20, 0), (-40, 0)]
MOVE_DISTANCE = 20
UP = 90
DOWN = 270
LEFT = 180
RIGHT = 0


class Snake:
    def __init__(self):
        self.all_segments = []
        self.create_snake()
        self.head = self.all_segments[0]

    def create_snake(self):
        for position in START:
            self.add_segment(position)

    def add_segment(self, position):
        segment = turtle.Turtle("square")
        segment.color("white")
        segment.penup()
        segment.goto(position)
        self.all_segments.append(segment)

    def grow_tail(self):
        self.add_segment(self.all_segments[-1].position())

    def move(self):
        for seg_num in range((len(self.all_segments) - 1), 0, -1):
            x_position = self.all_segments[seg_num - 1].xcor()
            y_position = self.all_segments[seg_num - 1].ycor()
            self.all_segments[seg_num].goto(x_position, y_position)
        self.head.forward(MOVE_DISTANCE)

    def up(self):
        if self.head.heading() != DOWN:
            self.head.setheading(UP)

    def down(self):
        if self.head.heading() != UP:
            self.head.setheading(DOWN)

    def right(self):
        if self.head.heading() != LEFT:
            self.head.setheading(RIGHT)

    def left(self):
        if self.head.heading() != RIGHT:
            self.head.setheading(LEFT)
