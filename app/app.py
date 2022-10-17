import webbrowser
from flask import Flask, render_template

app = Flask(__name__)


@app.route("/")
def home():
    return render_template("home.html")


def open_browser():
    webbrowser.open_new("http://localhost:8080/")


if __name__ == "__main__":
    open_browser()
    app.run(port=8080)
