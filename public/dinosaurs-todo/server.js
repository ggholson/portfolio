var express = require('express');
var fs = require('fs');
var app = express();
console.log(__dirname)
app.use(express.static(__dirname + '/client'));
app.use(express.bodyParser());

function createGuid() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
        var r = Math.random() * 16 | 0,
            v = c === 'x' ? r : (r & 0x3 | 0x8);
        return v.toString(16);
    });
}

app.get('/', function(req, res) {
    fs.readFile('index.html', function(err, data) {
        if (err) throw err;

        res.send(data.toString());
    });
});

app.get('/test', function(req, res) {
    var clay = {
        "title": "my dummy to do item",
        "completed": false,
        "id": "7590287345098237459087"
    }
    res.json(clay);
});

app.get('/items', function(req, res) {
    fs.readFile('data.json', function(err, data) {
        if (err) throw err;
        var dataitems = JSON.parse(data.toString());
        res.json(dataitems);
    });
});

app.get('/items/:id', function(req, res) {
    fs.readFile('data.json', function(err, data) {
        if (err) throw err;
        var dataitems = JSON.parse(data.toString());
        for (var i = 0; i < dataitems.length; i++) {
            if (dataitems[i].id === req.params.id) {
                res.json(dataitems[i]);
                return
            }
        };
    });
});

app.delete('/items/:id', function(req, res) {
    fs.readFile('data.json', function(err, data) {
        if (err) throw err;
        var dataitems = JSON.parse(data.toString());
        for (var i = 0; i < dataitems.length; i++) {
            if (dataitems[i].id === req.params.id) {
                dataitems.splice(i, 1);
                fs.writeFile('data.json', JSON.stringify(dataitems), function(err) {
                    if (err) throw err;
                    res.end();
                    return;
                });
            }
        };
    });
});

app.post('/items', function(req, res) {
    fs.readFile('data.json', function(err, data) {
        if (err) throw err;
        var dataitems = JSON.parse(data.toString());
        console.log(req.body.title);
        var newItem = {
            "title": req.body.title,
            "completed": false,
            "id": createGuid()
        };

        dataitems.push(newItem);
        fs.writeFile('data.json', JSON.stringify(dataitems), function(err) {
            if (err) throw err;
            res.end();
        });
    });
});

app.post('/items/:id', function(req, res) {
    fs.readFile('data.json', function(err, data) {
        if (err) throw err;
        var dataitems = JSON.parse(data.toString());
        for (var i = 0; i < dataitems.length; i++) {
            if (dataitems[i].id === req.params.id) {
                if (req.body.status === true || req.body.status === false) {
                    dataitems[i].completed = req.body.status;
                } else {
                    dataitems[i].title = req.body.title;
                }
            }
        };
        fs.writeFile('data.json', JSON.stringify(dataitems), function(err) {
            if (err) throw err;
            res.end();
        });
    });
});

console.log("Starting to listen");

var server = app.listen(3001, function() {
    console.log('Listening on port' + server.address().port);
});

console.log("Waiting for server to start")