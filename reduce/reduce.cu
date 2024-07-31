#include"cuda_runtime.h"
#include"device_launch_parameters.h"
#include <__clang_cuda_builtin_vars.h>
#include <climits>
#include <cstddef>
#include<iostream>
#include <limits>
#include <stdexcept>
#include <type_traits>
#include<vector>
#include<string>
#include<random>
#include<functional>
#include<tuple>
#include"cublas_v2.h"

template <typename T>
void check(T result, const char *function, const char *file, size_t line)
{
    if (result)
    {
        std::cerr << "CUDA error at " << file << ":" << line << " function " << function
                  << " error code: " << cudaGetErrorName(result)
                  << " error string: " << cudaGetErrorString(result) << std::endl;
        // Optionally, you might want to reset the CUDA error state
        // cudaGetLastError(); // To reset the error state
        exit(EXIT_FAILURE); // EXIT_FAILURE is more standard than 1
    }
}

#define CUDACHECK(val) do { check((val), #val, __FILE__, __LINE__); } while (0)

class CudaTimer 

{
private:
    cudaEvent_t start, stop;
    std::string m_kernalName;

public:
    // Constructor
    CudaTimer(const std::string& kernel_name = "") : m_kernalName(kernel_name){
        cudaEventCreate(&start);
        cudaEventCreate(&stop);
    }

    // Destructor
    ~CudaTimer() {
        cudaEventDestroy(start);
        cudaEventDestroy(stop);
    }

    // Start timing
    void startTiming() {
        cudaEventRecord(start, 0);
    }

    // Stop timing and return elapsed time in milliseconds
    float stopTiming() {
        cudaEventRecord(stop, 0);
        cudaEventSynchronize(stop);

        float milliseconds = 0;
        cudaEventElapsedTime(&milliseconds, start, stop);
        //std::cout<< m_kernalName << " elapsed time: " << milliseconds << " ms" << std::endl;
        return milliseconds;
        

    }
};


void printGPUInfo() {
    int deviceCount;
    cudaGetDeviceCount(&deviceCount);

    for (int i = 0; i < deviceCount; ++i) {
        cudaDeviceProp deviceProp;
        cudaGetDeviceProperties(&deviceProp, i);

        std::cout << "Device " << i << ": " << deviceProp.name << std::endl;
        std::cout << "Compute Capability: " << deviceProp.major << "." << deviceProp.minor << std::endl;
        std::cout << "Total Global Memory: " << deviceProp.totalGlobalMem / (1024 * 1024) << " MB" << std::endl;
        std::cout << "Shared Memory per Block: " << deviceProp.sharedMemPerBlock / 1024 << " KB" << std::endl;
        std::cout << "Max Threads per Block: " << deviceProp.maxThreadsPerBlock << std::endl;
        std::cout << "Max Block Dimensions: (" << deviceProp.maxThreadsDim[0] << ", " << deviceProp.maxThreadsDim[1] << ", " << deviceProp.maxThreadsDim[2] << ")" << std::endl;
        std::cout << "Max Grid Dimensions: (" << deviceProp.maxGridSize[0] << ", " << deviceProp.maxGridSize[1] << ", " << deviceProp.maxGridSize[2] << ")" << std::endl;
        std::cout << std::endl;
    }
}



template<typename T = int>
class Matrix
{
private:
    size_t m_row;
    size_t m_col;
    std::vector<T> m_data;
public:
    using value_type = T;
    enum class MatrixType
    {
        RowMajor,
        ColMajor
    };
    Matrix(size_t row,size_t col)  noexcept:m_row(row),m_col(col),m_data(row*col,T{}){}
    Matrix(size_t row,size_t col,std::vector<T> data) noexcept:m_row(row),m_col(col),m_data(data){}
    Matrix(size_t row,size_t col,T* data) noexcept:m_row(row),m_col(col),m_data(data,data+row*col){}
    Matrix(size_t row,size_t col,const T& value) noexcept:m_row(row),m_col(col),m_data(row*col,value){}
    Matrix(const Matrix& other)noexcept:m_row(other.m_row),m_col(other.m_col),m_data(other.m_data){}
    Matrix(Matrix&& other)noexcept:m_row(other.m_row),m_col(other.m_col),m_data(std::move(other.m_data)){}
    Matrix<T> & operator =(const Matrix<T> & matrix) noexcept
    {
        if(this != &matrix)
        {
            m_row = matrix.m_row;
            m_col = matrix.m_col;
            m_data = matrix.m_data;
        }
        return *this;
    }
    Matrix<T> & operator =(Matrix<T> && matrix) noexcept
    {
        if(this != &matrix)
        {
            m_row = matrix.m_row;
            m_col = matrix.m_col;
            m_data = std::move(matrix.m_data);
        }
        return *this;
    }
   
    const T& operator() (size_t row,size_t col) const noexcept
    {
        return m_data[row*m_col+col];
    }
    T& operator() (size_t row,size_t col) noexcept
    {
        // if(row >=m_row || col>=m_col )
        // {
        //     throw std::out_of_range("Matrix subscript out of range");
        // }
        return m_data[row*m_col+col];
    }
    const T& operator[] (size_t index) const noexcept
    {
        // if(index >=m_row*m_col )
        // {
        //     throw std::out_of_range("Matrix subscript out of range");
        // }
        return m_data[index];
    }
    T& operator[] (size_t index) noexcept
    {
        // if(index >=m_row*m_col)
        // {
        //     throw std::out_of_range("Matrix subscript out of range");
        // }
        return m_data[index];
    }
    std::vector<T>& data() const noexcept
    {
        return m_data;
    }
    T* data_ptr() noexcept
    {
        return m_data.data();
    }
    const T* data_ptr() const noexcept
    {
        return m_data.data();
    }
   
    
    void printfMatrix() const noexcept
    {
        for(size_t i = 0;i<m_row;++i)
        {
            for(size_t j = 0;j<m_col;++j)
            {
                std::cout<<m_data[i*m_col+j]<<" ";
            }
            std::cout<<std::endl;
        }
    }
    
    bool isEqual(const Matrix<T>& other) const noexcept
    {
        if(m_row != other.m_row || m_col != other.m_col)
        {
            return false;
        }
        for(size_t i = 0;i<m_row;++i)
        {
            for(size_t j = 0;j<m_col;++j)
            {
                if(m_data[i*m_col+j] != other.m_data[i*m_col+j])
                {
                    return false;
                }
            }
        }
        return true;
    }
    size_t row() const noexcept
    {
        return m_row;
    }
    size_t col() const noexcept
    {
        return m_col;
    }
    template<typename U>
    friend bool operator == (const Matrix<U> & one,const Matrix<U> & other) noexcept;

    Matrix<T> transpose() const noexcept
    {
        Matrix<T> result(m_col,m_row);
        for(size_t i = 0;i<m_row;++i)
        {
            for(size_t j = 0;j<m_col;++j)
            {
                result(j,i) = m_data[i*m_col+j];
            }
        }
        return result;
    }

    template<typename U>
    void deepCopy(const Matrix<U>& other) noexcept
    {
        m_row = other.row();
        m_col = other.col();
        m_data.resize(m_row*m_col);
        for(size_t i = 0;i<m_row;++i)
        {
            for(size_t j = 0;j<m_col;++j)
            {
                m_data[i*m_col+j] = other(i,j);
            }
        }
    }

};

// template<typename T, 
//          typename = std::enable_if_t<std::is_integral_v<T>>>
// bool operator == (const Matrix<T> & one,const Matrix<T> &other)  noexcept
// {
//     return one.isEqual(other);
// }

template<typename T>
bool operator == (const Matrix<T> & one,const Matrix<T> &other)  noexcept
{
     float epsilon = 1e-5;
     if (one.row() != other.row() || one.col() != other.col()) {
       return false;
     }
     for (size_t i = 0; i < one.row(); ++i) {
       for (size_t j = 0; j < one.col(); ++j) {
         if (std::abs(one(i, j) - other(i, j)) > epsilon) {
           return false;
         }
       }
     }
     return true;
}

template<typename U>
bool operator != (const Matrix<U> & one,const Matrix<U> &other)  noexcept
{
    return !(one==other);
}


template <typename U = int>
static Matrix<U> generateMatrix(size_t row, size_t col) {
  std::random_device rd;
  std::mt19937 gen(rd());
  std::uniform_int_distribution<int> dis(0, 10000);
  Matrix<U> matrix(row, col);
  for (size_t i = 0; i < row; ++i) {
    for (size_t j = 0; j < col; ++j) {
      matrix(i, j) = static_cast<U>(dis(gen));
    }
  }
  return matrix;
}


template<typename F,typename ... Args>
auto  test_kernel(F kernel,size_t row=1024,size_t col =1024,Args... args)
{
    float elapsed_time = 0.0f;
    auto matrix = generateMatrix<float>(row,col);
    Matrix<float>  result(matrix.row(),matrix.col());

    using VauleType = decltype(matrix)::value_type;
    size_t byteSize = matrix.row() * matrix.col() * sizeof(VauleType);

    VauleType* dev_idata;
    VauleType* dev_odata;

    CUDACHECK(cudaMalloc(reinterpret_cast<void**>(&dev_idata),byteSize));
    CUDACHECK(cudaMalloc(reinterpret_cast<void**>(&dev_odata),byteSize));
    CUDACHECK(cudaMemcpy(dev_idata,matrix.data_ptr(),byteSize,cudaMemcpyHostToDevice));

    dim3 threadsPerBlock(32,32);
    dim3 blocksPerGrid((matrix.col() + threadsPerBlock.x -1) /threadsPerBlock.x,
                       (matrix.row() + threadsPerBlock.y -1) /threadsPerBlock.y);
    CudaTimer timer("kernel");
    timer.startTiming();
    kernel<<<blocksPerGrid,threadsPerBlock>>>(dev_odata,dev_idata,matrix.row(),matrix.col(),args...);
    CUDACHECK(cudaGetLastError());
    CUDACHECK(cudaDeviceSynchronize());
    elapsed_time = timer.stopTiming();
    CUDACHECK(cudaMemcpy(result.data_ptr(),dev_odata,byteSize,cudaMemcpyDeviceToHost));
    CUDACHECK(cudaFree(dev_idata));
    CUDACHECK(cudaFree(dev_odata));
    return std::make_tuple(matrix,result,elapsed_time);
}



template<typename T>
struct Max{
    __device__ __host__ T operator()(const T &a,const T &b) const
    {
        return a>b?a:b;
    }
};

template <typename T>
struct Min{
    __device__ __host__ T operator()(const T &a,const T &b) const
    {
        return a<b?a:b;
    }
};

template <typename T>
struct Sum{
    __device__ __host__ T operator()(const T &a,const T &b) const
    {
        return a+b;
    }
};

template<typename T>

struct XOR{
    __device__ __host__ T operator()(const T &a,const T &b) const
    {
        return a^b;
    }
};






template<typename T,typename OP>
void reduce_cpu(T* odata, T* idata,size_t N,OP op)
{
    T result = idata[0];
    for(size_t i = 1;i<N;++i)
    {
        result = op(result,idata[i]);
    }
    *odata = result;
}


// only one block, and one thread to reduce.
//basic version
template<typename T,typename OP>
__global__ void reduce_1(T* odata, T* idata,size_t N, OP op)
{
    T result = idata[0];
    for(size_t i = 1;i<N;++i)
    {
        result = op(result,idata[i]);
    }
    *odata = result;
}



// use reduced tree to reduce data.
// use even threads to reduce data, and store the result in the first half of the data.
// 0 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15  stride = 1
// 1   5   9   13   17   21   25   29     stride = 2
// 6       22       38        54          stride = 4
// 28               92                    stride = 8 
// 120                                    

template<typename T,typename OP>
__global__ void reduce_2(T* odata, T* idata,size_t N, OP op)
{
    size_t tid = threadIdx.x;
    for(size_t stride = 1;stride < blockDim.x;stride *= 2)
    {
        if(threadIdx.x % (2*stride) == 0)
        {
            idata[tid] = op(idata[tid],idata[tid+stride]);
        }
        __syncthreads();
    }
    if(tid == 0)
    {
        *odata = idata[0];
    }
}


template<typename T,typename OP>
__global__ void reduce_3(T* odata, T* idata,size_t N, OP op)
{
    size_t tid = threadIdx.x;
    for(size_t stride = blockDim.x/2 ;stride > 1;stride /= 2)
    {
        if(threadIdx.x<stride)
        {
            idata[tid] = op(idata[tid],idata[tid+stride]);
        }
        __syncthreads();
    }
    if(tid == 0)
    {
        *odata = idata[0];
    }
}




#define LOOP_TEST(test_func,n,row,col,baseline_time) \
{\
    float elapsed_time = 0.0f;\
    for(int i=0;i<n;++i)\
    {\
        elapsed_time += test_func(row,col);\
    }\
    std::cout<<#test_func<<" Average elapsed time: "<<elapsed_time/n<<" ms"<<std::endl;\
    if(baseline_time > 0)\
    {\
        std::cout<<"Speedup: "<<baseline_time/(elapsed_time/n)<<std::endl;\
    }\
}

#define BASELINE_TEST(test_func,n,row,col) \
({\
    float elapsed_time = 0.0f;\
    for(int i=0;i<n;++i)\
    {\
        elapsed_time += test_func(row,col);\
    }\
    std::cout << #test_func << " average time: " << (elapsed_time / n) << " ms" << std::endl;\
    elapsed_time/n;\
}) 


void loop_test()
{
    const int N=2;
    //dummy test for warm up
    test_transpose_base();
    //std::vector<int> test_sizes = {32,64,128,256,512,1024,2048,4096,8192};
    std::vector<int> test_sizes{2048};
    std::cout<<"Loop test "<<N<<" times"<<std::endl;

    for(auto size : test_sizes)
    {
        std::cout<<"Matrix size: "<<size<<"x"<<size<<std::endl;
        size_t row = size;
        size_t col = size;
        float baseline = BASELINE_TEST(test_transpose_base,N,row,col);
        LOOP_TEST(test_copyMatrix, N,row,col,baseline);
        LOOP_TEST(test_cublasTransposeMatrix, N,row,col,baseline);
        LOOP_TEST(test_transpose_shared, N,row,col,baseline);
        //LOOP_TEST(test_transpose_stride, N,row,col,baseline);
        LOOP_TEST(test_transpose_shared_2, N,row,col,baseline);
        LOOP_TEST(test_transposeMatrix_shared_unroll, N, row, col, baseline);
        std::cout<<std::endl;
    }

    
}



int main()
{
    printGPUInfo();
    loop_test();
    return 0;
}