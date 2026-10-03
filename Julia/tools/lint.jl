# Static package checks: Aqua for package hygiene, JET for inferred errors.
using Aqua: Aqua
using JET: JET
using ProjectName: ProjectName
using Test: @testset

@testset "ProjectName lint" begin
    Aqua.test_all(ProjectName)
    JET.test_package(ProjectName; target_modules = (ProjectName,))
end
