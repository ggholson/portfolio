//Dinosaur Data for To-do list Dev/Iowa project

var allToDos = new Array();

function dinosave() {
    // save data to local storage
    localStorage.setItem("todoitems", JSON.stringify(allToDos));
}

function dinoload() {
    // load data from local storage
    allToDos = JSON.parse(localStorage.getItem("todoitems"));
    if (allToDos === null)
        allToDos = []
}



function createGuid() {
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
        var r = Math.random() * 16 | 0,
            v = c === 'x' ? r : (r & 0x3 | 0x8);
        return v.toString(16);
    });
}

function create(t, cb) {
    $.ajax({
        url: '/items/',
        type: "POST",
        data: JSON.stringify({
            title: t
        }),
        success: function(data) {
            cb(data);
        },
        contentType: "application/json"
    });
}

function getAll(cb) {
    $.get('/items', function(data) {
        allToDos = data;
        cb(allToDos);
    });
}

function get(id, cb) {
    $.get('/items/' + id, function(data) {
        var item = data;
        cb(item);
    });
}

function remove(id, cb) {
    $.ajax({
        url: '/items/' + id,
        type: "DELETE",
        success: function(data) {
            cb();
        }
    });

}

function setStatus(id, s, cb) {

    $.ajax({
        url: '/items/' + id,
        type: "POST",
        data: JSON.stringify({
            status: s
        }),
        success: function(data) {
            cb(data);
        },
        contentType: "application/json"
    });

}


function setTitle(id, t, cb) {

    $.ajax({
        url: '/items/' + id,
        type: "POST",
        data: JSON.stringify({
            title: t
        }),
        success: function(data) {
            cb(data);
        },
        contentType: "application/json"
    });
}


dinoload()