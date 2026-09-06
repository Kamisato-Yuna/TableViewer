"use strict";
var __printed = [], __currentDatabase = "test", __lastCursor = null;
function ObjectId(value) { if (!(this instanceof ObjectId)) return new ObjectId(value); value = value === undefined ? __newOID() : String(value); if (!/^[0-9a-fA-F]{24}$/.test(value)) throw new Error(__localized("ObjectId must be a 24-character hexadecimal string")); this.$oid = value.toLowerCase(); }
ObjectId.prototype.toString = function() { return this.$oid; };
function NumberLong(value) { if (!(this instanceof NumberLong)) return new NumberLong(value); this.$numberLong = String(value); }
NumberLong.prototype.toString = function() { return this.$numberLong; };
function NumberDecimal(value) { if (!(this instanceof NumberDecimal)) return new NumberDecimal(value); this.$numberDecimal = String(value); }
NumberDecimal.prototype.toString = function() { return this.$numberDecimal; };
function NumberInt(value) { return {$numberInt:String(value)}; }
function ISODate(value) { return {$date:new Date(value === undefined ? Date.now() : value).toISOString()}; }
function __encode(value, space) { return JSON.stringify(value, function(k,v) { return this[k] instanceof Date ? {$date:this[k].toISOString()} : v; }, space); }
function __decode(value) {
    if (Array.isArray(value)) return value.map(__decode);
    if (!value || typeof value !== "object") return value;
    if (Object.keys(value).length === 1) {
        if (value.$numberInt !== undefined || value.$numberDouble !== undefined) return Number(value.$numberInt ?? value.$numberDouble);
        if (value.$numberLong !== undefined) return NumberLong(value.$numberLong);
        if (value.$numberDecimal !== undefined) return NumberDecimal(value.$numberDecimal);
        if (value.$oid !== undefined) return ObjectId(value.$oid);
    }
    for (var key of Object.keys(value)) value[key] = __decode(value[key]);
    return value;
}
function __command(database, command) {
    var response = __decode(JSON.parse(__nativeCommand(database, __encode(command))));
    if (response.__tableviewerError) throw new Error(response.__tableviewerError);
    if (response.writeErrors && response.writeErrors.length) throw new Error(response.writeErrors[0].errmsg);
    if (response.writeConcernError) throw new Error(response.writeConcernError.errmsg);
    return response;
}
function print(...values) { __printed.push(values.map(v => typeof v === "string" ? v : __encode(v,2)).join(" ")); }
var printjson = print, console = {log:print, info:print, warn:print, error:print};
var EJSON = {stringify:__encode, parse:s => __decode(JSON.parse(s))};
function __alive(id) { return id !== null && id !== undefined && String(id) !== "0"; }
function Cursor(database, collection, command) {
    this.database = database; this.collection = collection; this.command = command;
    this.buffer = []; this.cursorID = null; this.started = false; this.seen = 0; this.maximum = 1000;
}
Cursor.prototype.limit = function(n) { if (this.started) throw new Error(__localized("The cursor has already started")); if (!Number.isInteger(n) || n < 0 || n > 1000) throw new Error(__localized("limit must be between 0 and 1000")); this.maximum = n || 1000; if (this.command.find) this.command.limit = this.maximum; return this; };
Cursor.prototype.skip = function(n) { if (this.started || !Number.isInteger(n) || n < 0) throw new Error(__localized("skip must be a nonnegative integer set before running")); this.command.skip = n; return this; };
Cursor.prototype.sort = function(order) { if (this.started) throw new Error(__localized("The cursor has already started")); this.command.sort = order; return this; };
Cursor.prototype.pretty = function() { return this; };
Cursor.prototype.close = function() { if (__alive(this.cursorID)) __command(this.database, {killCursors:this.collection,cursors:[this.cursorID]}); this.cursorID = null; };
Cursor.prototype.fill = function() {
    var reply;
    if (!this.started) {
        this.started = true;
        if (this.command.find) { this.command.limit = this.maximum; this.command.batchSize = 20; }
        reply = __command(this.database, this.command);
    } else if (__alive(this.cursorID)) reply = __command(this.database, {getMore:this.cursorID,collection:this.collection,batchSize:20});
    else return;
    if (!reply.cursor) throw new Error(__localized("The command returned no cursor"));
    this.cursorID = reply.cursor.id;
    this.buffer.push(...(reply.cursor.firstBatch || reply.cursor.nextBatch || []));
};
Cursor.prototype.hasNext = function() { if (this.seen >= this.maximum) { this.close(); return false; } if (!this.buffer.length) this.fill(); return this.buffer.length > 0; };
Cursor.prototype.next = function() { if (!this.hasNext()) return null; this.seen++; var value = this.buffer.shift(); if (this.seen >= this.maximum) this.close(); return value; };
Cursor.prototype.nextBatch = function(n) { var rows = []; while (rows.length < n && this.hasNext()) rows.push(this.next()); return rows; };
Cursor.prototype.toArray = function() { var rows = this.nextBatch(this.maximum); this.close(); return rows; };
Cursor.prototype.forEach = function(fn) { while (this.hasNext()) fn(this.next()); };
Cursor.prototype.count = function() { return __command(this.database,{count:this.collection,query:this.command.filter || {}}).n; };
function Collection(database, name) { this.database = database; this.name = name; }
Collection.prototype.find = function(filter = {}, projection) { var command = {find:this.name,filter:filter,maxTimeMS:15000}; if (projection) command.projection = projection; return new Cursor(this.database,this.name,command); };
Collection.prototype.findOne = function(filter = {}, projection) { return this.find(filter,projection).limit(1).toArray()[0] ?? null; };
Collection.prototype.aggregate = function(pipeline, options = {}) { return new Cursor(this.database,this.name,Object.assign({aggregate:this.name,pipeline:pipeline,cursor:{batchSize:20},maxTimeMS:15000},options)); };
Collection.prototype.countDocuments = function(filter = {}) { var result = this.aggregate([{$match:filter},{$count:"n"}]).toArray(); return result.length ? result[0].n : 0; };
Collection.prototype.estimatedDocumentCount = function() { return __command(this.database,{count:this.name}).n; };
Collection.prototype.insertOne = function(document) { return __command(this.database,{insert:this.name,documents:[document]}); };
Collection.prototype.insertMany = function(documents) { return __command(this.database,{insert:this.name,documents:documents}); };
Collection.prototype.updateOne = function(filter, update, options = {}) { return __command(this.database,{update:this.name,updates:[{q:filter,u:update,multi:false,upsert:options.upsert === true}]}); };
Collection.prototype.updateMany = function(filter, update, options = {}) { return __command(this.database,{update:this.name,updates:[{q:filter,u:update,multi:true,upsert:options.upsert === true}]}); };
Collection.prototype.replaceOne = Collection.prototype.updateOne;
Collection.prototype.deleteOne = function(filter) { return __command(this.database,{delete:this.name,deletes:[{q:filter,limit:1}]}); };
Collection.prototype.deleteMany = function(filter) { return __command(this.database,{delete:this.name,deletes:[{q:filter,limit:0}]}); };
Collection.prototype.getIndexes = function() { return new Cursor(this.database,this.name,{listIndexes:this.name,cursor:{batchSize:20}}).toArray(); };
Collection.prototype.createIndex = function(keys, options = {}) { var name = options.name || Object.entries(keys).map(([k,v]) => k+"_"+v).join("_"); return __command(this.database,{createIndexes:this.name,indexes:[Object.assign({key:keys,name:name},options)]}); };
Collection.prototype.drop = function() { return __command(this.database,{drop:this.name}); };
function Database(name) { this.name = name; }
Database.prototype.getName = function() { return this.name; };
Database.prototype.getCollection = function(name) { return new Collection(this.name,name); };
Database.prototype.getSiblingDB = function(name) { return __database(name); };
Database.prototype.runCommand = function(command) { return __command(this.name,command); };
Database.prototype.adminCommand = function(command) { return __command("admin",command); };
Database.prototype.hello = function() { return this.adminCommand({hello:1}); };
Database.prototype.stats = function() { return this.runCommand({dbStats:1}); };
Database.prototype.getCollectionNames = function() { return new Cursor(this.name,"$cmd.listCollections",{listCollections:1,nameOnly:true,cursor:{batchSize:20}}).toArray().map(c => c.name); };
Database.prototype.createCollection = function(name, options = {}) { return this.runCommand(Object.assign({create:name},options)); };
function __database(name) { return new Proxy(new Database(name),{get(target,key) { if (typeof key === "symbol" || key in target) return Reflect.get(target,key); return target.getCollection(key); }}); }
var db = __database(__currentDatabase);
function __useDatabase(name) { __currentDatabase = name; db = __database(name); return db; }
var rs = {status:() => __command("admin",{replSetGetStatus:1}),conf:() => __command("admin",{replSetGetConfig:1})};
function __render(value) {
    var output = __printed.join("\n");
    if (value instanceof Cursor) { __lastCursor = value; var rows = value.nextBatch(20); output += (output ? "\n" : "") + __encode(rows,2); if (value.buffer.length || __alive(value.cursorID)) output += __localized("\nEnter it to display the next batch."); }
    else if (value !== undefined) output += (output ? "\n" : "") + (typeof value === "string" ? value : __encode(value,2));
    return output;
}
