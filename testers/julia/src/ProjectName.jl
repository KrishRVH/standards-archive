"""
    ProjectName

Shapes with an area, dispatched on their concrete type.
"""
module ProjectName

export Circle, Rectangle, Shape, area, total_area

"""Any shape that has an [`area`](@ref)."""
abstract type Shape end

"""A circle with a non-negative radius."""
struct Circle{T <: Real} <: Shape
    radius::T
    function Circle(radius::T) where {T <: Real}
        radius >= zero(radius) || throw(DomainError(radius, "radius must be non-negative"))
        return new{T}(radius)
    end
end

"""An axis-aligned rectangle with non-negative sides."""
struct Rectangle{T <: Real} <: Shape
    width::T
    height::T
    function Rectangle(width::T, height::T) where {T <: Real}
        min(width, height) >= zero(T) || throw(DomainError((width, height), "sides must be non-negative"))
        return new{T}(width, height)
    end
end

"""
    area(shape::Shape)

Return the area of `shape`.
"""
function area end

area(circle::Circle) = pi * circle.radius^2
area(rectangle::Rectangle) = rectangle.width * rectangle.height

"""
    total_area(shapes)

Return the summed area of `shapes`, or zero for an empty collection.
"""
total_area(shapes) = sum(area, shapes; init = 0.0)

end
