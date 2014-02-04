# Nested

Nested is a DSL to create a restful API in a declarative way. It is implemented in ruby. The author has some strong opinions about REST/API.

## Quickstart

Nested provides you a bunch of keywords to declare the resources of your API. Most important are "singleton", "many" and "one".

```
class MyApi < Nested::App
  singleton :user
end
```

You just declared your first resource! But it does not do much right, so lets add a HTTP verb to make it accessible.

```
class MyApi < Nested::App
  singleton :user do
    get
  end
end
```

Now our resource is reachable by issuing a GET request to "/user". It still does not return any useful data. A resources is always backed by a model. Mostly you will use an array, hash or orm-instances (e.g. activerecord) as underlying model. The easiest way is to provide a block to your resource.

```
class MyApi < Nested::App
  singleton :user, ->{ {name: "joe"} } do
    get
  end
end
```

The model block will be invoked each time the resource is requested. We still do not get back the underlying model from our resource. In nested you have to explicitly whitelist which fields your want to expose for a resource.

```
class MyApi < Nested::App
  singleton :user, ->{ {id: 99, name: "joe"} } do
    serialize :id, :name
    get
  end
end
```

Congrats! You just created your first nested API. Checkout the other sections to get more information about different resource types, verbs, serialization and conditionals.

## Nested:App

In nested you implement your API as a normal ruby class which inherit from Nested::App

```
class MyApi < Nested::App
end
```

## Resources

### Singleton

A unique value.

```
class MyApi < Nested::App
  # the current user
  singleton :user do
    serialize :id, :email, :username

    # GET /user
    get
  end

  # session which is used to login/logout
  singleton :session do
    # perform login, POST /session
    post

    # perform logout, DELETE /session
    delete
  end
end
```

### Many

A list of values.

```
class MyApi < Nested::App
  many :tasks do
    serialize :id, :title, :description

    # GET /tasks
    get
  end
end
```

### One

A specific value of many resource.

```
class MyApi < Nested::App
  many :tasks do
    serialize :id, :title, :description

    # GET /tasks
    get

    one do
      # GET /tasks/:id
      get
    end
  end
end
```

One can only be used within a enclosing Many. One inherits its name and serialization information from the Many.

## Http Verbs

Nested supports all commonly used http verbs used in a resftul API. Call the verb as method inside the resource block to make the resource respond to that http verb.

```
class MyApi < Nested::App
  singleton :user do
    # respond to GET /user
    get

    # respond to POST /user
    post

    # respond to DELETE /user
    delete

    # respond to PUT /user
    put

    # respond to PATCH /user
    patch
end
```

You can pass a block to each http verb to impement the concret behavior.

```
class MyApi < Nested::App
  singleton :user, ->{ {name: "joe" } } do
    get do
      puts "i am a GET request"
    end

    delete do
      puts "and i am a DELETE one"
    end
  end
end
```

The http verb block can access the model of the resource as an instance variable.

```
class MyApi < Nested::App
  singleton :user, ->{ {name: "joe" } } do
    get do
      puts "my name is #{@user.name}"
    end
  end
end
```

The model is available in all http verb block. Except inpost. The post block has to return a new model.

```
class MyApi < Nested::App
  singleton :user do
    post do
      {name: "joe"}
    end
  end
end
```

Nested gives you access to http parameters through the params method as known from other frameworks and addition to this a useful shorthand.

```
class MyApi < Nested::App
  singleton :user, ->{ {name: "joe", age: 33 } } do
    put do
      @user.name = params[:new_name]
      @user.age = params[:age]
    end

    # same as

    put do |new_name, age|
      @user.name = new_name
      @user.age = age
    end
  end
end
```
