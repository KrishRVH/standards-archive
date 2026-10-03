using ProjectName
using Test

@testset "ProjectName" begin
    @testset "area dispatches on the shape type" begin
        @test area(Rectangle(2, 3)) == 6
        @test area(Circle(1.0)) ≈ pi
        @test area(Circle(0)) == 0
    end

    @testset "total_area" begin
        @test total_area(Shape[Rectangle(1, 2), Circle(1)]) ≈ 2 + pi
        @test total_area(Shape[]) == 0
    end

    @testset "rejects negative dimensions" begin
        @test_throws DomainError Circle(-1)
        @test_throws DomainError Rectangle(1, -1)
    end
end
