## Multiplication of operator * fun

function ultraiconversion{T}(g::Vector{T},m::Integer)
    if m==0 
        g 
    elseif m==1
        ultraiconversion(g)
    else
        backsubstitution!(MutableAlmostBandedOperator(Operator[USConversionOperator(0:m)]),copy(g))::Vector{T}
    end
end
function ultraconversion{T}(g::Vector{T},m::Integer)
    if m==0
        g 
    elseif m==1
        ultraconversion(g)
    else
        (USConversionOperator(0:m)*g)::Vector{T}
    end
end


*(A::InfiniteOperator,b::IFun)=IFun(ultraiconversion(A*ultraconversion(b.coefficients,domainspace(A).order),rangespace(A).order),b.domain)


*{T<:Operator}(A::Vector{T},b::IFun)=map(a->a*b,convert(Array{Any,1},A))