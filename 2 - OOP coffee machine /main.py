from menu import Menu, MenuItem
from coffee_maker import CoffeeMaker
from money_machine import MoneyMachine

run = True
item = Menu()
MenuItem.ingredients = item
print(Menu.get_items(item))

coffee = CoffeeMaker()
money = MoneyMachine()
cost = 0


def choose():
    global run, cost
    choice = input(f"What would you like to drink? {Menu.get_items(item)}: ")
    if choice == "off":
        run = False
    elif choice == "report":
        coffee.report()
        money.report()
        choose()
    elif not Menu.find_drink(item, choice) == "":
        cost = 0
        drink = Menu.find_drink(item, choice)
        if coffee.is_resource_sufficient(drink):
            def amount_cost():
                global cost
                for thing in item.menu:
                    if thing.name == drink.name:
                        cost += thing.cost
            amount_cost()
            print(cost)
            if money.make_payment(cost):
                coffee.make_coffee(drink)
            else:
                cost = 0
        else:
            print(f"Sorry for the inconvenience. Money returned.")
            choose()
    else:
        print("Something went wrong")


while run:
    choose()
