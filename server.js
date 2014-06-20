var express = require('express');
var fs = require('fs');
var app = express();

app.use(express.static(__dirname + '/client'));
app.use(express.static(__dirname + '/public'));
app.use(express.static(__dirname + '/js'));
app.use(express.static(__dirname + '/images'));

app.get('/r1', function(req, res) {
    fs.readFile('./data/r1slides.html', 'utf8', function(err, data) {
        res.send(data);
    });
});

app.get('/r2', function(req, res) {
    fs.readFile('./data/r2slides.html', 'utf8', function(err, data) {
        res.send(data);
    });
});

app.get('/r3', function(req, res) {
    fs.readFile('./data/r3slides.html', 'utf8', function(err, data) {
        res.send(data);
    });
});

app.get('/shell', function(req, res) {
    fs.readFile('./public/portfolio/shell/shell.c', function(err, data) {
        res.send(data);
    });
});

app.get('/sgp', function(req, res) {
    fs.readFile('./public/portfolio/sgp/vertexOps.vhd', function(err, data) {
        res.send(data);
    });
});

app.get('/robot', function(req, res) {
    fs.readFile('./public/portfolio/robot/robot.c', function(err, data) {
        res.send(data);
    });
});

app.listen(3000);