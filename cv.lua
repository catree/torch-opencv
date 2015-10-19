-- This file contains common vars and funcs

local ffi = require 'ffi'

function libPath(libName)
    if     ffi.os == 'Windows' then
        return 'lib/' .. libName .. '.dll'
    elseif ffi.os == 'OSX' then
        return 'lib/lib' .. libName .. '.dylib'
    else
        return 'lib/lib' .. libName .. '.so'
    end
end

ffi.cdef[[
struct TensorWrapper {
    void *tensorPtr;
    char typeCode;
};

struct TensorArray {
    struct TensorWrapper *tensors;
    short size;
};

void *malloc(size_t size);
void free(void *ptr);

void transfer_tensor(void *destination, void *source);

struct SizeWrapper {
    int width, height;
};

struct Size2fWrapper {
    float width, height;
};

struct TermCriteriaWrapper {
    int type, maxCount;
    double epsilon;
};

struct ScalarWrapper {
    double v0, v1, v2, v3;
};

struct Vec3dWrapper {
    double v0, v1, v2;
};

struct RectWrapper {
    int x, y, width, height;
};

struct PointWrapper {
    int x, y;
};

struct Point2fWrapper {
    float x, y;
};

struct RotatedRectWrapper {
    struct Point2fWrapper center;
    struct Size2fWrapper size;
    float angle;
};

struct MomentsWrapper {
    double m00, m10, m01, m20, m11, m02, m30, m21, m12, m03;
    double mu20, mu11, mu02, mu30, mu21, mu12, mu03;
    double nu20, nu11, nu02, nu30, nu21, nu12, nu03;
};

struct TensorPlusDouble {
    struct TensorWrapper tensor;
    double val;
};

struct TensorArrayPlusFloat {
    struct TensorArray tensors;
    float val;
};

struct RectPlusInt {
    struct RectWrapper rect;
    int val;
};

struct IntArray {
    int *data;
    int size;
};

struct FloatArray {
    float *data;
    int size;
};

struct PointArray {
    struct PointWrapper *data;
    int size;
};

struct RectArray {
    struct RectWrapper *data;
    int size;
};

struct FloatArrayOfArrays {
    float **pointers;
    float *realData;
    int dims;
};

int getIntMax();

struct PointArrayOfArrays {
    struct PointWrapper **pointers;
    struct PointWrapper *realData;
    int dims;
    int *sizes;
};

]]

local C = ffi.load(libPath('Common'))

cv = {}

require 'cv.constants'

cv.INT_MAX = C.getIntMax()

--- ***************** Tensor <=> Mat conversion *****************

local tensor_CV_code_by_letter = {
    [66] = cv.CV_8U , -- Byte
    [70] = cv.CV_32F, -- Float
    [68] = cv.CV_64F, -- Double
    [73] = cv.CV_32S, -- Int
    [83] = cv.CV_16S, -- Short
    [67] = cv.CV_8S , -- Char
}

local tensor_type_by_CV_code = {
    [cv.CV_8U ] = "Byte",
    [cv.CV_32F] = "Float",
    [cv.CV_64F] = "Double",
    [cv.CV_32S] = "Int",
    [cv.CV_16S] = "Short",
    [cv.CV_8S ] = "Char"
}

cv.EMPTY_WRAPPER = ffi.new("struct TensorWrapper", nil)
cv.EMPTY_MULTI_WRAPPER = ffi.new("struct TensorArray", nil)

function cv.tensorType(tensor)
    -- get the first letter of Tensor type
    local letter = tensor:type():byte(7)

    if letter == 76 then
        error("Sorry, LongTensors aren't supported. Consider using IntTensor")
    end

    return tensor_CV_code_by_letter[letter]
end

local
function empty_tensor_of_type(code)
    if code == cv.CV_16U then
        error("Sorry, cv::Mats of type CV_16U aren't supported.")
    end

    return torch[tensor_type_by_CV_code[code] .. "Tensor"]()
end

-- torch.RealTensor ---> tensor:cdata(), tensor_type_CV_code
local 
function prepare_for_wrapping(tensor)
    return tensor:cdata(), cv.tensorType(tensor)
end

-- torch.RealTensor ---> struct TensorWrapper/struct TensorArray
function cv.wrap_tensors(...)
    if not ... then
        return cv.EMPTY_WRAPPER
    end

    local args = {...}
    if type(args[1]) == "table" then
        args = args[1]
    end

    if #args == 1 then
        return ffi.new("struct TensorWrapper", prepare_for_wrapping(args[1]))
    else
        wrapper = ffi.new("struct TensorArray")
        wrapper.size = #args
        wrapper.tensors = C.malloc(#args * ffi.sizeof("struct TensorWrapper *"))

        for i, tensor in ipairs(args) do
            wrapper.tensors[i-1] = cv.wrap_tensors(tensor)
        end

        return wrapper
    end
end

-- struct TensorWrapper(s) ---> torch.RealTensor
function cv.unwrap_tensors(wrapper, toTable)
    if ffi.typeof(wrapper) == ffi.typeof("struct TensorWrapper") then
        -- handle single tensor
        retval = empty_tensor_of_type(wrapper.typeCode)
        C.transfer_tensor(retval:cdata(), wrapper.tensorPtr)
        return retval
    else
        -- handle multiple tensors
        if wrapper.tensors == nil then
            -- return nothing in case of a nullptr
            return
        end

        retval = {}
        for i = 0,wrapper.size-1 do
            temp_tensor = empty_tensor_of_type(wrapper.tensors[i].typeCode)
            C.transfer_tensor(temp_tensor:cdata(), wrapper.tensors[i].tensorPtr)
            table.insert(retval, temp_tensor)
        end

        C.free(wrapper.tensors)
        if toTable then
            return retval
        else
            return unpack(retval)
        end
    end
end

-- see filter_depths in opencv2/imgproc.hpp
function cv.checkFilterCombination(src, ddepth)
    local srcType = cv.tensorType(src)
    if srcType == cv.CV_8U then
        return ddepth == cv.CV_16S or ddepth >= cv.CV_32F or ddepth == -1
    elseif srcType == cv.CV_16S or srcType == cv.CV_32F then
        return ddepth >= cv.CV_32F or ddepth == -1
    elseif srcType == cv.CV_64F then
        return ddepth == cv.CV_64F or ddepth == -1
    else
        return false
    end
end

--- ***************** Wrappers for small OpenCV classes *****************
-- Use these for passing into functions. Example:

-- r = cv.Rect{10, 10, 15, 25}
-- OR
-- r = cv.Rect{x=10, y=10, width=15, height=25}
-- OR
-- r1 = cv.Rect{x=10, y=10, width=15, height=25}
-- r2 = cv.Rect(r1)

-- same with most of the following wrappers (see OpenCV defs)

-- TODO: generate these straight in the code

function cv.Rect(values)
    return ffi.new('struct RectWrapper', values)
end

function cv.TermCriteria(data)
    return ffi.new('struct TermCriteriaWrapper', data)
end

function cv.Scalar(data)
    return ffi.new('struct ScalarWrapper', data)
end

function cv.Moments(data)
    return ffi.new('struct MomentsWrapper', data)
end

function cv.Size(data)
    return ffi.new('struct SizeWrapper', data)
end

function cv.Size2f(data)
    return ffi.new('struct Size2fWrapper', data)
end

function cv.Vec3d(data)
    return ffi.new('struct Vec3dWrapper', data)
end

function cv.Point(data)
    return ffi.new('struct PointWrapper', data)
end

function cv.Point2f(data)
    return ffi.new('struct Point2fWrapper', data)
end

function cv.RotatedRect(data)
    return ffi.new('struct RotatedRectWrapper', data)
end

--- ***************** Other helper structs *****************

--[[
Makes an <IntArray, FloatArray, ...> from a table of numbers.
Generally, if you're calling a function that uses Array many
times, consider reusing the retval of this function.

Example (not very realistic):

cv.calcHist{images=im, channels={3,3,1,3,4}, ......}

OR

ch = cv.newArray('Int', {3,3,1,3,4})
for i = 1,1e8 do
    cv.calcHist{images=im, channels=ch, ...}
    ......
--]]
function cv.newArray(elemType, data)
    local retval
    local fullTypeName
    local shortTypeName

    if elemType:byte(3) == 46 then
        -- there's a period after 2 symbols: likely "cv.Something"
        shortTypeName = elemType:sub(4)
        fullTypeName = 'struct ' .. shortTypeName .. 'Wrapper'
        retval = ffi.new('struct ' .. shortTypeName .. 'Array')
    else
        -- C primitive type, such as 'Int' or 'Float'
        fullTypeName = elemType:lower()
        retval = ffi.new('struct ' .. elemType .. 'Array')
    end
    
    retval.data = ffi.gc(C.malloc(#data * ffi.sizeof(fullTypeName)), C.free)
    retval.size = #data

    if elemType:byte(3) == 46 then
        for i, value in ipairs(data) do
            retval.data[i-1] = cv[shortTypeName](data[i])
        end
    else
        for i, value in ipairs(data) do
            retval.data[i-1] = data[i]
        end
    end

    return retval
end

-- TODO: function cv.newArrayOfArrays(elemType, data)

-- example: table of tables of numbers ---> struct FloatArrayOfArrays
function cv.numberArrayOfArrays(elemType, data)
    local retval = ffi.new('struct ' .. elemType .. 'ArrayOfArrays')

    -- first, compute relative addresses
    retval.pointers = ffi.gc(C.malloc(#data * ffi.sizeof(elemType:lower() .. '*') + 1), C.free)
    retval.pointers[0] = nil
    
    for i, row in ipairs(data) do
        data[i] = data[i-1] + #row
    end
    retval.realData = ffi.gc(C.malloc(totalElemSize * ffi.sizeof(elemType:lower())), C.free)

    retval.pointers[0] = retval.realData
    local counter = 0
    for i, row in ipairs(data) do
        -- fill data
        for j, elem in ipairs(row) do
            retval.realData[counter] = elem
            counter = counter + 1
        end
        -- transform relative addresses to absolute
        retval.pointers[i] = retval.pointers[i] + retval.realData
    end
end


function cv.arrayToLua(array, outputType, output)
    local retval

    if output then
        for i = 1,array.size do
            output[i] = array.data[i-1]
        end

        C.free(array.data)
        return output
    end
    
    if     outputType == 'table' then
        retval = {}
    elseif outputType == 'Tensor' then
        -- ctype has the form 'ctype<struct IntArray>'
        ctype = tostring(ffi.typeof(array))
        local typeStart = 14
        local typeEnd = ctype:find('Arr') - 1
        retval = torch[ctype:sub(typeStart, typeEnd) .. 'Tensor'](array.size)
    end

    for i = 1,array.size do
        retval[i] = array.data[i-1]
    end

    C.free(array.data)
    return retval
end

--- ***************** Classes *****************

do
    local Algorithm = torch.class('Algorithm')

    function Algorithm:__init()
        self.ptr = cv.NULLPTR
    end

    function Algorithm:clear()
        C.algo_clear(self.ptr)
    end


end


return cv