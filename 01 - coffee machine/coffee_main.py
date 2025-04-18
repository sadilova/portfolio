MENU = {
    "espresso": {
        "ingredients": {
            "water": 50,
            "coffee": 18,
        },
        "cost": 1.5,
    },
    "latte": {
        "ingredients": {
            "water": 200,
            "milk": 150,
            "coffee": 24,
        },
        "cost": 2.5,
    },
    "cappuccino": {
        "ingredients": {
            "water": 250,
            "milk": 100,
            "coffee": 24,
        },
        "cost": 3.0,
    }
}


PENNY = 0.01
NICKEL = 0.05
DIME = 0.1
QUARTER = 0.25

# machine specs
machine = {
    'ingredients': {
        'milk': 500,
        'water': 1000,
        'coffee': 200},
    'money': 0
}

total = 0


def make_coffee():
    global total
    global MENU

    def report():
        print(f"Water: {machine['ingredients']['water']} mL \n"
              f"Milk: {machine['ingredients']['milk']} mL \n"
              f"Coffee: {machine['ingredients']['coffee']} g \n"
              f"Earned: ${machine['money']} \n")

    def resource_check():
        global MENU
        check = True
        if choice in MENU:
            if 'milk' in MENU[choice]['ingredients']:
                if machine['ingredients']['milk'] < MENU[choice]['ingredients']['milk']:
                    check = False
                    print("Sorry, there is not enough milk!")
            elif machine['ingredients']['water'] < MENU[choice]['ingredients']['water']:
                check = False
                print("Sorry, there is not enough water!")
            elif machine['ingredients']['coffee'] < MENU[choice]['ingredients']['coffee']:
                check = False
                print("Sorry, there is not enough coffee!")
        else:
            print("There's been an error in selection process.")

        if not check:
            run == False

        for value in MENU[choice]['ingredients']:
            a = machine['ingredients'][value]
            b = MENU[choice]['ingredients'][value]
            machine['ingredients'][value] = a - b

    def coins():
        global total
        global MENU

        print("Please insert coins: ")
        pennies = int(input("How many pennies? "))
        nickels = int(input("Nickels: "))
        dimes = int(input("Dimes: "))
        quarters = int(input("Quarters: "))
        total = round((pennies * PENNY) + (nickels * NICKEL) + (dimes * DIME) + (quarters * QUARTER), 2)

        if total > MENU[choice]['cost']:
            money_return = round(total - MENU[choice]['cost'], 2)
            print(f"Here is your change: ${money_return}")
        elif total < MENU[choice]['cost']:
            more = round(MENU[choice]['cost'] - total, 2)
            print(f"The amount you have inserted is insufficient. You need ${more} more.\n")
            add = input(f"Do you want to insert more? Y or N: ").lower()
            if add == "y":
                coins()
            elif add == "n":
                print(f"Sorry, we cannot serve you. Here is your money back: ${total}")
        else:
            print("Something else is wrong.")

    run = True

    while run:
        choice = input("What coffee would you like? Choose espresso, latte, or cappuccino: ").lower()
        if choice == "off":
            run = False
        elif choice == "report":
            report()
        else:
            resource_check()
            coins()
            machine['money'] += MENU[choice]['cost']

            print(f"Here is your {choice}! ☕ Enjoy! \n")


make_coffee()
